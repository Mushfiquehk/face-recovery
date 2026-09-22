"""face-pipeline whoop-auth | whoop-pull | score | build-dataset"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone

from face_pipeline import config, dataset, photos, scoring, whoop


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="face-pipeline")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("whoop-auth", help="Connect your WHOOP account (opens a browser once)")

    pull = sub.add_parser("whoop-pull", help="Download WHOOP Recovery and sleep records")
    pull.add_argument("--days", type=int, default=365, help="How far back to pull (default 365)")

    score = sub.add_parser("score", help="Score photos with the app's pinned model and prompt")
    score.add_argument("--limit", type=int, help="Score at most N new photos (try 1 first)")

    sub.add_parser("build-dataset", help="Pair photos with WHOOP Recovery and write the dataset")

    args = parser.parse_args(argv)
    cfg = config.load()

    if args.command == "whoop-auth":
        whoop.authorize(cfg)

    elif args.command == "whoop-pull":
        end = datetime.now(timezone.utc)
        counts = whoop.pull(cfg, end - timedelta(days=args.days), end)
        print(f"Pulled {counts['recovery']} recoveries and {counts['sleep']} sleeps "
              f"into {cfg.whoop_data_dir}")

    elif args.command == "score":
        found = _discover(cfg)
        todo = [p for p in found if p.captured_at and not scoring.load_cached(cfg, p)]
        if args.limit is not None:
            todo = todo[:args.limit]
        print(f"{len(found)} photos, {len(todo)} to score")
        for i, photo in enumerate(todo, 1):
            try:
                result = scoring.score(cfg, photo)
            except Exception as error:  # keep going; a retry only re-scores what failed
                print(f"[{i}/{len(todo)}] {photo.path.name}: FAILED {error}")
                continue
            s = result["signals"]
            print(f"[{i}/{len(todo)}] {photo.path.name}: tiredness {s['holistic_tiredness']}, "
                  f"usable {result['capture_quality']['usable']}")

    elif args.command == "build-dataset":
        recoveries, sleeps = whoop.load_pulled(cfg)
        manifest = dataset.build(cfg, _discover(cfg), recoveries, sleeps)
        print(f"{manifest['paired']} of {manifest['photos_found']} photos paired "
              f"({manifest['paired_days']} days, {manifest['scored']} scored). "
              f"{manifest['unmatched']} unmatched, reasons in unmatched.csv.")
        print(f"Dataset: {cfg.dataset_output_dir}")


def _discover(cfg: config.Config) -> list[photos.Photo]:
    if not cfg.photo_input_dir.exists():
        raise SystemExit(f"Photo folder {cfg.photo_input_dir} does not exist yet; create it and add photos.")
    return photos.discover(cfg.photo_input_dir, cfg.photo_timezone)


if __name__ == "__main__":
    main()
