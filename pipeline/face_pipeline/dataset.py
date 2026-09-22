"""Pairs photos with WHOOP Recovery and writes the research dataset.

Pairing rule: a photo is paired with the Recovery of the most recent main (non-nap) sleep that
ended before it was taken, provided it was taken within `max_hours_after_wake` of waking. The
Recovery is therefore one WHOOP had already computed that morning: nothing from later in the day
or later nights leaks into the pair. Photos slightly before the recorded wake time are allowed,
because WHOOP often logs waking a few minutes after the user is actually up.
"""

from __future__ import annotations

import csv
import json
import shutil
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from face_pipeline import scoring
from face_pipeline.config import Config
from face_pipeline.photos import Photo, to_jpeg

WAKE_TOLERANCE = timedelta(minutes=30)


@dataclass(frozen=True)
class Pairing:
    sleep: dict | None
    recovery: dict | None
    reason: str | None  # why it did not pair; None when it did


def parse_ts(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def pair(captured_at: datetime, sleeps: list[dict], recoveries_by_sleep: dict[str, dict],
         max_hours_after_wake: float) -> Pairing:
    candidates = [s for s in sleeps
                  if not s.get("nap") and s.get("end")
                  and parse_ts(s["end"]) - WAKE_TOLERANCE <= captured_at]
    if not candidates:
        return Pairing(None, None, "no WHOOP sleep ended before this photo")
    sleep = max(candidates, key=lambda s: parse_ts(s["end"]))
    if captured_at - parse_ts(sleep["end"]) > timedelta(hours=max_hours_after_wake):
        return Pairing(sleep, None, f"taken more than {max_hours_after_wake:g}h after waking")
    recovery = recoveries_by_sleep.get(sleep["id"])
    if recovery is None:
        return Pairing(sleep, None, "no WHOOP Recovery for that sleep")
    if recovery.get("score_state") != "SCORED" or not recovery.get("score"):
        return Pairing(sleep, recovery, f"WHOOP Recovery {recovery.get('score_state', 'missing').lower()}")
    return Pairing(sleep, recovery, None)


def build(cfg: Config, photos: list[Photo], recoveries: list[dict], sleeps: list[dict]) -> dict:
    out = cfg.dataset_output_dir
    images = out / "images"
    shutil.rmtree(images, ignore_errors=True)  # generated output: always rebuilt whole
    images.mkdir(parents=True)

    by_sleep = {r["sleep_id"]: r for r in recoveries if r.get("sleep_id")}
    rows: list[dict] = []
    unmatched: list[dict] = []

    for photo in sorted(photos, key=lambda p: p.captured_at or datetime.max.replace(tzinfo=timezone.utc)):
        source = str(photo.path.relative_to(cfg.photo_input_dir))
        if photo.captured_at is None:
            unmatched.append({"source_file": source, "captured_at": "", "reason": "no EXIF capture time"})
            continue
        result = pair(photo.captured_at, sleeps, by_sleep, cfg.max_hours_after_wake)
        if result.reason:
            unmatched.append({"source_file": source, "captured_at": photo.captured_at.isoformat(),
                              "reason": result.reason})
            continue
        rows.append(_row(cfg, photo, source, result.sleep, result.recovery, images))

    # Canonical Scan: the earliest photo paired to each night, mirroring the app's default.
    seen: set[str] = set()
    for row in rows:
        row["is_canonical"] = row["sleep_id"] not in seen
        seen.add(row["sleep_id"])

    _write_csv(out / "dataset.csv", rows)
    with (out / "dataset.jsonl").open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
    _write_csv(out / "unmatched.csv", unmatched, ["source_file", "captured_at", "reason"])

    manifest = {
        "built_at": datetime.now(timezone.utc).isoformat(),
        "photos_found": len(photos),
        "paired": len(rows),
        "paired_days": len(seen),
        "scored": sum(1 for r in rows if r["prompt_version"]),
        "unmatched": len(unmatched),
        "pairing_rule": {
            "max_hours_after_wake": cfg.max_hours_after_wake,
            "wake_tolerance_minutes": WAKE_TOLERANCE.total_seconds() / 60,
            "naps_excluded": True,
            "requires_score_state": "SCORED",
        },
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


def _row(cfg: Config, photo: Photo, source: str, sleep: dict, recovery: dict, images: Path) -> dict:
    local = photo.captured_at
    wake = parse_ts(sleep["end"])
    name = f"{local:%Y-%m-%d_%H%M%S}_{photo.sha256[:8]}.jpg"
    (images / name).write_bytes(to_jpeg(photo.path))

    rec = recovery["score"]
    sleep_score = sleep.get("score") or {}
    scored = scoring.load_cached(cfg, photo) or {}
    signals = scored.get("signals", {})
    quality = scored.get("capture_quality", {})
    run = scored.get("scoring_run", {})

    return {
        "photo_id": photo.sha256[:16],
        "image": f"images/{name}",
        "source_file": source,
        "captured_at": local.isoformat(),
        "local_date": local.date().isoformat(),
        "time_source": photo.time_source,
        "wake_at": wake.isoformat(),
        "minutes_after_wake": round((local - wake).total_seconds() / 60),
        "is_canonical": False,  # set after all rows are known
        "whoop_recovery": rec.get("recovery_score"),
        "whoop_hrv_rmssd_milli": rec.get("hrv_rmssd_milli"),
        "whoop_resting_heart_rate": rec.get("resting_heart_rate"),
        "whoop_spo2_percentage": rec.get("spo2_percentage"),
        "whoop_skin_temp_celsius": rec.get("skin_temp_celsius"),
        "whoop_user_calibrating": rec.get("user_calibrating"),
        "whoop_sleep_performance_percentage": sleep_score.get("sleep_performance_percentage"),
        "sleep_id": sleep["id"],
        "cycle_id": recovery.get("cycle_id"),
        **{key: signals.get(key) for key, _ in scoring.SIGNALS},
        "holistic_tiredness": signals.get("holistic_tiredness"),
        "capture_lighting": quality.get("lighting"),
        "capture_sharpness": quality.get("sharpness"),
        "face_fully_visible": quality.get("face_fully_visible"),
        "usable": quality.get("usable"),
        "scoring_provider": run.get("provider"),
        "scoring_model": run.get("model_id"),
        "prompt_version": run.get("prompt_version"),
        "schema_version": run.get("schema_version"),
    }


def _write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    fields = fields or (list(rows[0]) if rows else ["photo_id"])
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
