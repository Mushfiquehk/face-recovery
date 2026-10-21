"""Finds photos in the drop folder and dates them from EXIF.

A photo with no EXIF capture time is never guessed from file dates: that would be the
pipeline's equivalent of a Date-Adjusted scan, which research datasets exclude (CONTEXT.md).

The app writes its photos without EXIF, so a folder exported from the app is dated from the
`scans.json` beside it instead. Scans the app marks Date-Adjusted stay undated here.
"""

from __future__ import annotations

import hashlib
import io
import json
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
    time_source: str  # "exif+offset", "exif+assumed-zone", "app-export", "date-adjusted" or "missing"


def discover(folder: Path, assumed_zone: str | None = None) -> list[Photo]:
    zone: tzinfo = ZoneInfo(assumed_zone) if assumed_zone else _local_zone()
    paths = sorted(p for p in folder.rglob("*")
                   if p.is_file() and p.suffix.lower() in EXTENSIONS and not p.name.startswith("."))
    exported = app_export_scans(folder)
    out = []
    for p in paths:
        photo = _read(p, zone)
        scan = exported.get(p)
        if photo.captured_at is None and scan and scan.get("captured_at"):
            adjusted = bool(scan.get("is_date_adjusted"))
            captured_at = None if adjusted else datetime.fromisoformat(scan["captured_at"].replace("Z", "+00:00"))
            photo = Photo(path=p, sha256=photo.sha256, captured_at=captured_at,
                          time_source="date-adjusted" if adjusted else "app-export")
        out.append(photo)
    return out


def app_export_scans(folder: Path) -> dict[Path, dict]:
    """{photo path: scan record} from every app `scans.json` under `folder`."""
    records: dict[Path, dict] = {}
    for manifest in folder.rglob("scans.json"):
        try:
            scans = json.loads(manifest.read_text()).get("scans", [])
        except (OSError, ValueError):
            continue
        for scan in scans:
            if scan.get("photo"):
                records[manifest.parent / scan["photo"]] = scan
    return records


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
