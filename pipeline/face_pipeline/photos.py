"""Finds photos in the drop folder and dates them from EXIF.

A photo with no EXIF capture time is never guessed from file dates: that would be the
pipeline's equivalent of a Date-Adjusted scan, which research datasets exclude (CONTEXT.md).
"""

from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone, tzinfo
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageOps
from pillow_heif import register_heif_opener

register_heif_opener()

EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif"}

# EXIF tag ids
_EXIF_IFD = 0x8769
_DATETIME = 0x0132
_DATETIME_ORIGINAL = 0x9003
_OFFSET_TIME_ORIGINAL = 0x9011


@dataclass(frozen=True)
class Photo:
    path: Path
    sha256: str
    captured_at: datetime | None  # timezone-aware, or None when EXIF has no capture time
    time_source: str  # "exif+offset", "exif+assumed-zone", or "missing"


def discover(folder: Path, assumed_zone: str | None = None) -> list[Photo]:
    zone: tzinfo = ZoneInfo(assumed_zone) if assumed_zone else _local_zone()
    paths = sorted(p for p in folder.rglob("*")
                   if p.is_file() and p.suffix.lower() in EXTENSIONS and not p.name.startswith("."))
    return [_read(p, zone) for p in paths]


def _read(path: Path, zone: tzinfo) -> Photo:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    captured_at, source = None, "missing"
    try:
        with Image.open(path) as img:
            exif = img.getexif()
            sub = exif.get_ifd(_EXIF_IFD)
            raw = sub.get(_DATETIME_ORIGINAL) or exif.get(_DATETIME)
            offset = sub.get(_OFFSET_TIME_ORIGINAL)
        if raw:
            naive = datetime.strptime(str(raw).strip(), "%Y:%m:%d %H:%M:%S")
            if offset:
                captured_at, source = naive.replace(tzinfo=_parse_offset(str(offset))), "exif+offset"
            else:
                captured_at, source = naive.replace(tzinfo=zone), "exif+assumed-zone"
    except (OSError, ValueError):
        pass
    return Photo(path=path, sha256=digest, captured_at=captured_at, time_source=source)


def _parse_offset(text: str) -> timezone:
    sign = -1 if text.startswith("-") else 1
    hours, minutes = text.lstrip("+-").split(":")
    return timezone(sign * timedelta(hours=int(hours), minutes=int(minutes)))


def _local_zone() -> tzinfo:
    return datetime.now().astimezone().tzinfo or timezone.utc


def to_jpeg(path: Path, long_edge: int | None = None, quality: int = 90) -> bytes:
    """Upright RGB JPEG with all metadata stripped (no GPS leaves the machine or the dataset)."""
    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img).convert("RGB")
        if long_edge and max(img.size) > long_edge:
            img.thumbnail((long_edge, long_edge), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality)
        return buf.getvalue()
