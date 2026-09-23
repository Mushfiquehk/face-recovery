# face-recovery

Generates a daily recovery score from sleep using a face scan.

## Project scope

This project includes:

1. **Native iOS app** for taking a morning face photo and testing recovery scoring on-device.
2. **Training/data pipeline work** (same repository) to pair user photos with WHOOP recovery data for experimentation.
3. **Prompt-first image LLM scoring** as the initial baseline before iterative tuning.

## Domain language and decisions

- [`CONTEXT.md`](./CONTEXT.md) is the glossary. Use its terms exactly.
- [`docs/adr/`](./docs/adr) records why the non-obvious choices were made.
- [`docs/implementation-plan.md`](./docs/implementation-plan.md) is the v1 build plan.

## Configuration

Config is split, and the split matters:

- **The iOS app** reads no config files. The OpenRouter key is entered once in Settings and stored
  in the iOS Keychain. Model, pinned provider and seed are compiled in, and recorded on every
  Scoring Run.
- **The Python pipeline** reads `.env` on your Mac. Copy `.env.example` to `.env` and fill it in;
  `.env` is gitignored. Its `SCORING_*` values must match the app's, or re-scored Signals will not
  be comparable with the app's.

## Reporting notes

Use `notes/report-notes.md` during implementation and experiments.  
Add notes for each stage so they can be reused in the academic report.

## Needs Attention

Before the first build can run on a phone:

1. **Xcode toolchain** - `xcode-select` currently points at Command Line Tools:
   `sudo xcode-select -s /Applications/Xcode.app`
2. **Signing** - sign in with a free Apple ID in Xcode to create a Personal Team.
   Builds expire after 7 days and must be re-run from Xcode; push notifications and
   iCloud are unavailable on this tier.
3. **OpenRouter key** - create one and enter it in the app's Settings screen.
   Review account-level prompt-logging and training settings before scanning a real face.

For the research strand (not needed for the app):

4. **WHOOP developer credentials** in `.env`.
5. **Historical photos** to backfill, each associable with a WHOOP Recovery value.

The pipeline itself lives in [`pipeline/`](./pipeline/README.md): WHOOP pull, photo pairing and
dataset build.
