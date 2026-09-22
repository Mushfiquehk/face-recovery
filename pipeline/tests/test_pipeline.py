import csv
import json
import os
import re
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from PIL import Image

from face_pipeline import config, dataset, photos, scoring, whoop

UTC = timezone.utc
REPO = Path(__file__).resolve().parents[2]


def sleep(id, end, nap=False):
    return {"id": id, "end": end.isoformat().replace("+00:00", "Z"), "nap": nap,
            "score": {"sleep_performance_percentage": 90}}


def recovery(sleep_id, score=65, state="SCORED"):
    return {"sleep_id": sleep_id, "cycle_id": 1, "score_state": state,
            "score": {"recovery_score": score, "hrv_rmssd_milli": 50.0, "resting_heart_rate": 55,
                      "user_calibrating": False} if state == "SCORED" else None}


WAKE_1 = datetime(2026, 9, 1, 6, 30, tzinfo=UTC)
WAKE_2 = datetime(2026, 9, 2, 7, 0, tzinfo=UTC)
SLEEPS = [sleep("s1", WAKE_1), sleep("s2", WAKE_2), sleep("nap", WAKE_2 + timedelta(hours=7), nap=True)]
BY_SLEEP = {"s1": recovery("s1", 40), "s2": recovery("s2", 80)}


@pytest.mark.parametrize("taken, expected", [
    (WAKE_1 + timedelta(minutes=20), "s1"),
    (WAKE_1 - timedelta(minutes=10), "s1"),  # just before recorded wake: tolerated
    (WAKE_2 + timedelta(hours=3), "s2"),
])
def test_pairs_with_most_recent_main_sleep(taken, expected):
    result = dataset.pair(taken, SLEEPS, BY_SLEEP, 4)
    assert result.reason is None and result.sleep["id"] == expected


def test_never_pairs_with_a_later_night():
    result = dataset.pair(WAKE_1 - timedelta(hours=2), SLEEPS, BY_SLEEP, 4)
    assert result.reason == "no WHOOP sleep ended before this photo"


def test_rejects_photos_long_after_waking_and_ignores_naps():
    # After the nap ends but 8h after the main sleep: the nap must not rescue it.
    result = dataset.pair(WAKE_2 + timedelta(hours=8), SLEEPS, BY_SLEEP, 4)
    assert result.sleep["id"] == "s2" and "after waking" in result.reason


def test_unscored_recovery_is_not_paired():
    result = dataset.pair(WAKE_1 + timedelta(minutes=5), SLEEPS,
                          {"s1": recovery("s1", state="PENDING_SCORE")}, 4)
    assert result.reason == "WHOOP Recovery pending_score"


def write_photo(path: Path, taken: datetime | None, offset: str | None = None):
    img = Image.new("RGB", (64, 48), (200, 150, 120))
    exif = Image.Exif()
    if taken:
        sub = exif.get_ifd(0x8769)
        sub[0x9003] = taken.strftime("%Y:%m:%d %H:%M:%S")
        if offset:
            sub[0x9011] = offset
    img.save(path, exif=exif)


def test_exif_dating(tmp_path):
    write_photo(tmp_path / "a.jpg", datetime(2026, 9, 1, 7, 0), "-04:00")
    write_photo(tmp_path / "b.jpg", datetime(2026, 9, 1, 7, 0))
    write_photo(tmp_path / "c.jpg", None)
    a, b, c = photos.discover(tmp_path, "America/Toronto")
    assert a.captured_at == datetime(2026, 9, 1, 11, 0, tzinfo=UTC) and a.time_source == "exif+offset"
    assert b.captured_at == a.captured_at and b.time_source == "exif+assumed-zone"
    assert c.captured_at is None and c.time_source == "missing"


@pytest.fixture
def cfg(tmp_path):
    base = config.load()
    return replace(base, root=tmp_path, photo_input_dir=tmp_path / "photos",
                   dataset_output_dir=tmp_path / "dataset", whoop_data_dir=tmp_path / "whoop",
                   scores_dir=tmp_path / "scores", photo_timezone="UTC", max_hours_after_wake=4)


def test_build_end_to_end(cfg):
    cfg.photo_input_dir.mkdir()
    write_photo(cfg.photo_input_dir / "first.jpg", datetime(2026, 9, 1, 6, 45))
    write_photo(cfg.photo_input_dir / "second.jpg", datetime(2026, 9, 1, 6, 50))
    write_photo(cfg.photo_input_dir / "evening.jpg", datetime(2026, 9, 1, 19, 0))
    write_photo(cfg.photo_input_dir / "undated.jpg", None)
    found = photos.discover(cfg.photo_input_dir, "UTC")

    # A cached Scoring Run for one photo is joined in; the other stays unscored.
    first = next(p for p in found if p.path.name == "first.jpg")
    cfg.scores_dir.mkdir()
    scoring.cache_path(cfg, first).write_text(json.dumps({
        "signals": {k: 10 for k, _ in scoring.SIGNALS} | {"holistic_tiredness": 30},
        "capture_quality": {"lighting": 80, "sharpness": 70, "face_fully_visible": True, "usable": True},
        "scoring_run": {"provider": "CoreWeave", "model_id": "m", "prompt_version": "v1", "schema_version": "v1"},
    }))

    manifest = dataset.build(cfg, found, list(BY_SLEEP.values()), SLEEPS)
    assert (manifest["paired"], manifest["paired_days"], manifest["scored"], manifest["unmatched"]) == (2, 1, 1, 2)

    rows = list(csv.DictReader((cfg.dataset_output_dir / "dataset.csv").open()))
    assert [r["source_file"] for r in rows] == ["first.jpg", "second.jpg"]
    assert [r["is_canonical"] for r in rows] == ["True", "False"]
    assert rows[0]["whoop_recovery"] == "40" and rows[0]["holistic_tiredness"] == "30"
    assert rows[0]["minutes_after_wake"] == "15" and rows[1]["holistic_tiredness"] == ""
    for r in rows:
        with Image.open(cfg.dataset_output_dir / r["image"]) as img:
            assert img.format == "JPEG" and not img.getexif()  # metadata stripped

    reasons = {r["source_file"]: r["reason"] for r in csv.DictReader((cfg.dataset_output_dir / "unmatched.csv").open())}
    assert reasons == {"evening.jpg": "taken more than 4h after waking", "undated.jpg": "no EXIF capture time"}


class FakeResponse:
    def __init__(self, body, status=200):
        self.body, self.status_code, self.headers = body, status, {}

    def json(self):
        return self.body

    def raise_for_status(self):
        assert self.status_code < 400


class FakeSession:
    def __init__(self, pages):
        self.pages, self.calls = pages, []

    def get(self, url, headers, params, timeout):
        self.calls.append((url, dict(params)))
        return FakeResponse(self.pages[len(self.calls) - 1])


def test_whoop_pagination_follows_next_token(cfg, monkeypatch):
    monkeypatch.setattr(whoop, "_access_token", lambda c: "tok")
    session = FakeSession([
        {"records": [{"id": 1}], "next_token": "abc"},
        {"records": [{"id": 2}], "next_token": None},
    ])
    now = datetime(2026, 9, 22, tzinfo=UTC)
    records = whoop.fetch_collection(cfg, "/v2/recovery", now - timedelta(days=1), now, session)
    assert records == [{"id": 1}, {"id": 2}]
    assert session.calls[0][0] == "https://api.prod.whoop.com/developer/v2/recovery"
    assert "nextToken" not in session.calls[0][1] and session.calls[1][1]["nextToken"] == "abc"
    assert session.calls[0][1]["limit"] == 25


def test_prompt_matches_app():
    swift = Path(os.getenv("FACE_RECOVERY_APP_DIR", REPO / "FaceRecovery")) / "Scoring" / "ScoringPrompt.swift"
    if not swift.exists():
        pytest.skip(f"{swift} not present")
    source = swift.read_text()
    body = re.search(r'static let text = """\n(.*?)\n(\s*)"""', source, re.S)
    indent = body.group(2)
    text = "\n".join(line.removeprefix(indent) for line in body.group(1).split("\n"))
    assert text == scoring.PROMPT_TEXT
    assert f'static let version = "{scoring.PROMPT_VERSION}"' in source
