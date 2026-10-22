import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from face_pipeline import sleep_model
from face_pipeline.photos import Photo

UTC = timezone.utc


def test_icc_separates_stable_from_noisy_signals():
    rng = np.random.default_rng(0)
    days = rng.normal(size=12)
    stable = [[d + rng.normal(scale=0.1) for _ in range(3)] for d in days]
    noisy = [[rng.normal() for _ in range(3)] for _ in days]
    assert sleep_model.icc(stable) > 0.9
    assert sleep_model.icc(noisy) < 0.3
    assert np.isnan(sleep_model.icc([[1.0], [2.0]]))  # no session with repeats: nothing to judge


def test_prior_anchored_fit_moves_only_as_far_as_the_data_supports():
    rng = np.random.default_rng(1)
    z = rng.normal(size=(40, 2))
    y = 60 + 6 * z[:, 0] + rng.normal(scale=2, size=40)  # truth: +6 and 0
    prior = np.array([-4.0, 2.0])
    assert np.array_equal(sleep_model.fit_weights(z, y, 60, prior, float("inf")), prior)
    loose = sleep_model.fit_weights(z, y, 60, prior, 1.0)
    tight = sleep_model.fit_weights(z, y, 60, prior, 1000.0)
    assert loose[0] == pytest.approx(6, abs=1)
    assert np.abs(tight - prior).max() < np.abs(loose - prior).max()


def photo(name, when):
    return Photo(path=Path(name), sha256=name, captured_at=when, time_source="exif+offset")


def test_sessions_group_photos_minutes_apart():
    t = datetime(2026, 9, 1, 7, tzinfo=UTC)
    photos = [photo("a", t), photo("b", t + timedelta(minutes=20)), photo("c", t + timedelta(hours=5)),
              photo("d", None)]
    assert [[p.sha256 for p in s] for s in sleep_model.sessions(photos)] == [["a", "b"], ["c"], ["d"]]


def test_explanation_adds_up_exactly():
    model = {"startingValue": 60.0, "contributionClamp": 3.0, "signals": [
        {"id": "under_eye_shadow", "name": "Darkness under the eyes", "higherMeans": "darker under the eyes",
         "lowerMeans": "lighter under the eyes", "typicalDeviation": 2.0, "weight": -4.0},
        {"id": "brow_gap", "name": "Upper eyelid position", "higherMeans": "upper eyelids lower",
         "lowerMeans": "upper eyelids higher", "typicalDeviation": 0.01, "weight": -2.0},
    ]}
    value, parts = sleep_model.explain({"under_eye_shadow": 13.0, "brow_gap": 0.25},
                                       {"under_eye_shadow": 10.0, "brow_gap": 0.30}, model)
    shadow, brow = parts
    assert shadow["points"] == pytest.approx(-6.0) and shadow["words"] == "darker under the eyes"
    assert brow["points"] == pytest.approx(6.0)  # 5 typical deviations, clamped to 3
    assert value == pytest.approx(60.0 + sum(p["points"] for p in parts))


def test_perturbations_change_light_not_geometry(tmp_path):
    src = tmp_path / "face.jpg"
    Image.new("RGB", (40, 30), (180, 140, 120)).save(src)
    darker = sleep_model.perturb(src, "darker", tmp_path / "out")
    warmer = sleep_model.perturb(src, "warmer", tmp_path / "out")
    with Image.open(src) as a, Image.open(darker) as d, Image.open(warmer) as w:
        assert d.size == a.size
        assert sum(d.getpixel((5, 5))) < sum(a.getpixel((5, 5)))
        r, _, b = w.getpixel((5, 5))
        r0, _, b0 = a.getpixel((5, 5))
        assert r - b > r0 - b0


def test_shipped_model_matches_the_app_contract():
    model = json.loads(sleep_model.MODEL_PATH.read_text())
    assert model["measurementVersion"] == sleep_model.measurement_version()
    assert {"version", "startingValue", "contributionClamp", "signals"} <= set(model)
    for s in model["signals"]:
        assert {"id", "name", "higherMeans", "lowerMeans", "typicalDeviation", "weight"} <= set(s)
        assert s["typicalDeviation"] > 0
