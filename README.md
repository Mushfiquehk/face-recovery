# face-recovery

Predicts your WHOOP sleep performance from a morning face scan, measured on the phone, and
shows exactly which facial signs moved the number.

## Project scope

This project includes:

1. **Native iOS app** that takes a morning face photo, measures it on the device with Apple Vision
   and pixel arithmetic, and shows a Sleep Prediction with one Contribution per facial Signal.
2. **Research pipeline** (same repository) that pairs photos with WHOOP data, compiles the app's
   own measurement code into a Mac tool, and fits the Sleep Model the app ships (ADR 0005).
3. Earlier scans were rated by an image LLM; those ratings are kept for history and export only.

## Domain language and decisions

- [`CONTEXT.md`](./CONTEXT.md) is the glossary. Use its terms exactly.
- [`docs/adr/`](./docs/adr) records why the non-obvious choices were made.
- [`docs/implementation-plan.md`](./docs/implementation-plan.md) is the v1 build plan.

## Configuration

Config is split, and the split matters:

- **The iOS app** reads no config files and needs no key: photos never leave the phone. The
  Sleep Model is `FaceRecovery/Analysis/SleepModel.json`, written by `face-pipeline autoresearch`.
- **The Python pipeline** reads `.env` on your Mac. Copy `.env.example` to `.env` and fill it in;
  `.env` is gitignored. `SCORING_*` only matters for re-scoring photos with the old LLM prompt.

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
3. **Scan protocol** - glasses off, facing a window or white light, same spot each morning. The app
   flags anything else as a photo that does not count.

For the research strand (not needed for the app):

4. **WHOOP developer credentials** in `.env`.
5. **Dated morning photos**: app exports copied into `data/photos/`, then
   `face-pipeline autoresearch` to refit the Sleep Model.

The pipeline itself lives in [`pipeline/`](./pipeline/README.md): WHOOP pull, photo pairing and
dataset build.
