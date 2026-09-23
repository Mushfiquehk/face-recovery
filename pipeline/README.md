# Research pipeline

Pairs photos of your face with **WHOOP Recovery** to build the research dataset. Terms follow
[`CONTEXT.md`](../CONTEXT.md). Nothing here feeds the app: WHOOP Recovery is never shown as, or
blended into, a Recovery Score.

## Setup

```sh
cd pipeline
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
```

Fill in `.env` at the repo root (copy `.env.example`). For WHOOP:

1. Create an app at <https://developer-dashboard.whoop.com>.
2. Add the redirect URI `http://localhost:8080/whoop/callback` (must match `WHOOP_REDIRECT_URI`
   exactly) and enable the `read:recovery`, `read:sleep`, `read:cycles` and `read:profile` scopes.
3. Put the Client ID and Secret into `WHOOP_CLIENT_ID` / `WHOOP_CLIENT_SECRET`.

## Run

```sh
.venv/bin/face-pipeline whoop-auth          # once: opens a browser, saves tokens to data/whoop/
.venv/bin/face-pipeline whoop-pull --days 365
# drop photos into data/photos/ (subfolders fine; JPEG, PNG, HEIC)
.venv/bin/face-pipeline score --limit 1     # optional: Absolute Signals, same model/prompt as the app
.venv/bin/face-pipeline build-dataset
```

`score` is cached per photo hash in `data/scores/`, so re-running only scores new photos and
never re-scores an old one (Absolute Signals never change once produced).

## Output: `data/dataset/`

| File | Contents |
|---|---|
| `images/` | Every paired photo as an upright JPEG, all metadata (incl. GPS) stripped |
| `dataset.csv` / `.jsonl` | One row per paired photo: capture time, WHOOP Recovery, HRV, RHR, SpO2, skin temp, sleep performance, and Absolute Signals + Capture Quality when scored |
| `unmatched.csv` | Every photo that did not pair, with the reason |
| `manifest.json` | Counts and the pairing rule used |

## Pairing rule

A photo pairs with the Recovery of the most recent main (non-nap) WHOOP sleep that **ended before
it was taken**, if taken within `MAX_HOURS_AFTER_WAKE` (default 4) of waking; up to 30 minutes
*before* the recorded wake time is tolerated. Recovery must be `SCORED`. So every pair uses a
Recovery WHOOP already had that morning — nothing from later leaks in. The earliest photo per
night is marked `is_canonical`, mirroring the app's Canonical Scan default.

Photos with no EXIF capture time are excluded rather than dated from file timestamps, the
equivalent of the app's Date-Adjusted exclusion. Screenshots, messaging-app saves and some edited
exports lose EXIF; export originals from Photos ("Export Unmodified Original") to keep it.

EXIF times without an offset are read in `PHOTO_TIMEZONE` (default: this Mac's zone). Photos
taken while travelling in another zone are only correct if the camera wrote an offset, which
iPhones do.

## Tests

```sh
.venv/bin/pytest tests
```

`test_prompt_matches_app` fails if `face_pipeline/scoring.py` drifts from the app's
`ScoringPrompt.swift`; it skips when the app source is not checked out.
