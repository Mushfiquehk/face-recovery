"""Produces Absolute Signals for a photo exactly as the app does.

PROMPT_TEXT, the schema and the request body mirror FaceRecovery/Scoring/*.swift. Any drift makes
pipeline-scored Signals incomparable with app-scored ones, so `tests/test_scoring.py` checks the
prompt against the Swift source whenever it is present. Bump the versions together with the app.
"""

from __future__ import annotations

import base64
import json
from datetime import datetime, timezone
from pathlib import Path

import requests

from face_pipeline.config import Config
from face_pipeline.photos import Photo, to_jpeg

PROMPT_VERSION = "v1"
SCHEMA_VERSION = "v1"
SCHEMA_NAME = "face_scan_rating"
IMAGE_LONG_EDGE = 1024
JPEG_QUALITY = 80  # UIImage.jpegData(compressionQuality: 0.8)

SIGNALS = (
    ("under_eye_darkness", "Under-eye darkness"),
    ("under_eye_puffiness", "Under-eye puffiness"),
    ("facial_puffiness", "Facial puffiness"),
    ("eye_redness", "Eye redness"),
    ("skin_dullness", "Skin dullness"),
)

PROMPT_TEXT = """\
You are rating a single photograph of a human face for a personal recovery-tracking study.

Rate ONLY what is directly visible in this photograph. You are not diagnosing anything and
you have no information about this person beyond the image.

Rate each of the following 0-100. For every one of them, 0 means the characteristic is
entirely absent and 100 means it is as pronounced as you have ever seen on a human face.
Higher always means MORE pronounced:

- under_eye_darkness: darkness or discolouration of the skin under the eyes
- under_eye_puffiness: swelling or bagging of the skin under the eyes
- facial_puffiness: overall swelling or water retention across the face
- eye_redness: redness of the visible sclera
- skin_dullness: lack of brightness, evenness or luminosity in the skin

Then rate:
- holistic_tiredness: 0-100, your overall impression of how tired this face looks, judged
  as a whole rather than by adding up the characteristics above.

Rules:
- Judge only appearance. Do NOT infer or mention sleep, health, lifestyle, alcohol, stress,
  age, illness or any cause for what you see.
- Use the full 0-100 range. Do not cluster every rating near the middle.
- Rate this face as it appears, not relative to any other face or any imagined baseline.

Finally, assess the PHOTOGRAPH itself, honestly and independently of the face in it:
- lighting: 0-100, how adequately and evenly the face is lit for judging skin tone
- sharpness: 0-100, how much fine detail is resolved around the eyes and skin
- face_fully_visible: true only if the whole face, including both eyes and the full
  under-eye area, is unobstructed and within frame
- usable: true only if the six ratings above can be made with reasonable confidence from
  this photograph

You must fill in the capture quality block even when the face is unreadable. If the photo is
too dark, too blurred, obstructed, or contains no face, set usable to false and still give
your best numeric ratings rather than refusing.

Respond with JSON matching the provided schema and nothing else."""


def _rating(description: str) -> dict:
    return {"type": "integer", "minimum": 0, "maximum": 100, "description": description}


def schema() -> dict:
    properties = {key: _rating(f"{name}, 0-100, higher is more pronounced") for key, name in SIGNALS}
    properties["holistic_tiredness"] = _rating("Overall impression of tiredness, 0-100, higher is more tired")
    properties["capture_quality"] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "lighting": _rating("Adequacy and evenness of lighting, 0-100"),
            "sharpness": _rating("Fine detail resolved around eyes and skin, 0-100"),
            "face_fully_visible": {
                "type": "boolean",
                "description": "Whole face including both eyes and the full under-eye area is in frame and unobstructed",
            },
            "usable": {
                "type": "boolean",
                "description": "The ratings can be made with reasonable confidence from this photograph",
            },
        },
        "required": ["lighting", "sharpness", "face_fully_visible", "usable"],
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": properties,
        "required": [key for key, _ in SIGNALS] + ["holistic_tiredness", "capture_quality"],
    }


def request_body(cfg: Config, jpeg: bytes) -> dict:
    data_url = "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()
    return {
        "model": cfg.scoring_model,
        "provider": {"order": [cfg.scoring_provider], "allow_fallbacks": False},
        "seed": cfg.scoring_seed,
        "temperature": 0,
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": SCHEMA_NAME, "strict": True, "schema": schema()},
        },
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": PROMPT_TEXT},
            {"type": "image_url", "image_url": {"url": data_url}},
        ]}],
    }


def cache_path(cfg: Config, photo: Photo) -> Path:
    return cfg.scores_dir / f"{photo.sha256}.json"


def load_cached(cfg: Config, photo: Photo) -> dict | None:
    path = cache_path(cfg, photo)
    return json.loads(path.read_text()) if path.exists() else None


def score(cfg: Config, photo: Photo) -> dict:
    """One Scoring Run. Cached by photo hash: Absolute Signals never change once produced."""
    if cached := load_cached(cfg, photo):
        return cached
    cfg.require("openrouter_api_key")
    jpeg = to_jpeg(photo.path, long_edge=IMAGE_LONG_EDGE, quality=JPEG_QUALITY)
    requested_at = datetime.now(timezone.utc).isoformat()
    response = requests.post(
        f"{cfg.openrouter_base_url}/chat/completions",
        headers={
            "Authorization": f"Bearer {cfg.openrouter_api_key}",
            "Content-Type": "application/json",
            "X-Title": "Face Recovery",
        },
        json=request_body(cfg, jpeg),
        timeout=120,
    )
    raw = response.text
    body = response.json()
    if "error" in body or not response.ok:
        raise RuntimeError(f"OpenRouter {response.status_code}: {body.get('error', raw)}")
    parsed = json.loads(body["choices"][0]["message"]["content"])

    def clamp(v) -> int:
        return max(0, min(100, int(v)))

    quality = parsed["capture_quality"]
    record = {
        "sha256": photo.sha256,
        "signals": {key: clamp(parsed[key]) for key, _ in SIGNALS}
        | {"holistic_tiredness": clamp(parsed["holistic_tiredness"])},
        "capture_quality": {
            "lighting": clamp(quality["lighting"]),
            "sharpness": clamp(quality["sharpness"]),
            "face_fully_visible": bool(quality["face_fully_visible"]),
            "usable": bool(quality["usable"]),
        },
        "scoring_run": {
            "provider": body.get("provider") or cfg.scoring_provider,
            "model_id": cfg.scoring_model,
            "seed": cfg.scoring_seed,
            "prompt_version": PROMPT_VERSION,
            "schema_version": SCHEMA_VERSION,
            "requested_at": requested_at,
            "raw_response_json": raw,
        },
    }
    path = cache_path(cfg, photo)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2))
    return record
