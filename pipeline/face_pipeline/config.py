"""Reads `.env` (see `.env.example`). Relative paths resolve against the directory holding `.env`,
so the pipeline behaves the same whichever directory it is run from."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import find_dotenv, load_dotenv


@dataclass(frozen=True)
class Config:
    root: Path

    openrouter_api_key: str | None
    openrouter_base_url: str
    scoring_model: str
    scoring_provider: str
    scoring_seed: int

    whoop_client_id: str | None
    whoop_client_secret: str | None
    whoop_redirect_uri: str
    whoop_api_base_url: str

    photo_input_dir: Path
    dataset_output_dir: Path
    whoop_data_dir: Path
    scores_dir: Path

    # Photo EXIF times are local wall-clock with no zone unless the camera wrote an offset.
    # Empty means "this Mac's local zone".
    photo_timezone: str | None
    # A photo more than this long after waking is not a morning scan and is not paired.
    max_hours_after_wake: float

    def require(self, *names: str) -> None:
        missing = [n for n in names if not getattr(self, n)]
        if missing:
            env = ", ".join(n.upper() for n in missing)
            raise SystemExit(f"Missing {env} in {self.root / '.env'} (see .env.example).")


def load() -> Config:
    env_path = find_dotenv(usecwd=True)
    if env_path:
        load_dotenv(env_path)
        root = Path(env_path).resolve().parent
    else:
        root = Path.cwd()

    def path(name: str, default: str) -> Path:
        p = Path(os.getenv(name) or default).expanduser()
        return p if p.is_absolute() else (root / p).resolve()

    return Config(
        root=root,
        openrouter_api_key=os.getenv("OPENROUTER_API_KEY") or None,
        openrouter_base_url=os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"),
        scoring_model=os.getenv("SCORING_MODEL", "google/gemini-3.1-flash-lite"),
        scoring_provider=os.getenv("SCORING_PROVIDER", "Google AI Studio"),
        scoring_seed=int(os.getenv("SCORING_SEED", "42")),
        whoop_client_id=os.getenv("WHOOP_CLIENT_ID") or None,
        whoop_client_secret=os.getenv("WHOOP_CLIENT_SECRET") or None,
        whoop_redirect_uri=os.getenv("WHOOP_REDIRECT_URI", "http://localhost:8080/whoop/callback"),
        whoop_api_base_url=os.getenv("WHOOP_API_BASE_URL", "https://api.prod.whoop.com"),
        photo_input_dir=path("PHOTO_INPUT_DIR", "./data/photos"),
        dataset_output_dir=path("DATASET_OUTPUT_DIR", "./data/dataset"),
        whoop_data_dir=path("WHOOP_DATA_DIR", "./data/whoop"),
        scores_dir=path("SCORES_DIR", "./data/scores"),
        photo_timezone=os.getenv("PHOTO_TIMEZONE") or None,
        max_hours_after_wake=float(os.getenv("MAX_HOURS_AFTER_WAKE", "4")),
    )
