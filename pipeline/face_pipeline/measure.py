"""Runs the app's own on-device measurement (FaceMeasurement.swift) on this Mac.

The tool is compiled from the app source plus `measure/main.swift`, so research numbers are the
numbers the phone would produce (ADR 0005). It is rebuilt whenever either source changes, and
results are cached per photo and per build, so a changed measurement never mixes with an old one.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP_SOURCE = REPO / "FaceRecovery" / "Analysis" / "FaceMeasurement.swift"
CLI_SOURCE = Path(__file__).with_name("measure") / "main.swift"
BATCH = 64  # photos per tool invocation


def source_hash() -> str:
    digest = hashlib.sha256()
    for path in (APP_SOURCE, CLI_SOURCE):
        digest.update(path.read_bytes())
    return digest.hexdigest()[:12]


def tool(work_dir: Path) -> Path:
    """Path to the compiled tool for the current sources, building it if needed."""
    binary = work_dir / "bin" / f"face-measure-{source_hash()}"
    if not binary.exists():
        binary.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", str(APP_SOURCE), str(CLI_SOURCE), "-o", str(binary)],
                       check=True, capture_output=True, text=True)
    return binary


def measure(paths: list[Path], work_dir: Path) -> dict[Path, dict]:
    """{photo path: {"measurement": ...} or {"error": ...}}, cached by photo content and build."""
    build = source_hash()
    cache_path = work_dir / f"measurements-{build}.jsonl"
    cache: dict[str, dict] = {}
    if cache_path.exists():
        for line in cache_path.read_text().splitlines():
            record = json.loads(line)
            cache[record["sha256"]] = record

    digests = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    todo = [p for p in paths if digests[p] not in cache]
    if todo:
        binary = tool(work_dir)
        with cache_path.open("a") as f:
            for start in range(0, len(todo), BATCH):
                chunk = todo[start:start + BATCH]
                out = subprocess.run([str(binary), *map(str, chunk)], check=True,
                                     capture_output=True, text=True).stdout
                for path, line in zip(chunk, out.splitlines()):
                    record = json.loads(line)
                    record["sha256"] = digests[path]
                    record.pop("path", None)
                    cache[record["sha256"]] = record
                    f.write(json.dumps(record) + "\n")
    return {p: cache[digests[p]] for p in paths}
