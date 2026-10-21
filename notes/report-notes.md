# Report Notes

Use this file to capture implementation and experiment notes for the academic report.

## 1) iOS Photo Capture Flow

- Date: 2026-09-22
- What was implemented or changed: v1 of the iOS app, all nine steps of
  `docs/implementation-plan.md`. XcodeGen-generated project (`project.yml`, the `.xcodeproj` is
  not committed); Settings with a Keychain-backed OpenRouter key and a connection test;
  `ScoringService` calling OpenRouter with the pinned provider, fixed seed and a strict JSON
  schema; SwiftData persistence of Face Scans, Absolute Signals, Capture Quality and Scoring
  Runs; front-camera capture with an oval framing guide; Backfill from the photo library with
  EXIF dating and Date-Adjusted flagging; Personal Baseline and Recovery Score computed at read
  time; History and day detail with Canonical Scan re-designation; export of photos + `scans.json`.
- Test device + iOS version: built against the iOS 27.0 SDK (Xcode 27.0), deployment target
  iOS 26.0. Verified on the iPhone 17 Pro simulator only — **not yet run on a physical device.**
- Result: clean build, no warnings. App launches and the History empty state renders. Three
  things were verified headlessly rather than by eye:
  - The emitted JSON schema is exactly the six 0-100 integers plus the `capture_quality` object,
    `strict: true` and `additionalProperties: false` throughout.
  - Response decoding round-trips a realistic payload, and out-of-range ratings from a
    misbehaving provider are clamped to 0-100 before they can reach baseline arithmetic.
  - The scoring arithmetic was exercised against an in-memory store (20 assertions, all passing):
    a day at baseline scores 70, +10 on every Signal scores 55, -10 scores 85; Baseline Forming
    falls back to `100 - mean(Signals)` below three qualifying scans; Unusable and Date-Adjusted
    scans are stored but excluded from the Personal Baseline; the baseline window caps at 14;
    days with no scan are absent rather than interpolated; the earliest scan of a day is Canonical
    by default, a re-designation is recorded and wins, and a later backfill of an earlier photo
    does not silently take Canonical status back.
- Issues/observations:
  - **Nothing has been scored by the real model yet.** No OpenRouter key has been exercised, so
    step 4 of the plan — the go/no-go on whether GLM 5.3 Flash moves sensibly with obvious
    inputs — is still open, as is the seed-determinism check in plan section 10.
  - The Personal Baseline for a given scan is built only from qualifying Canonical Scans of
    *strictly earlier* days. This was a deliberate choice beyond what the plan specified: a
    baseline that included the day being scored, or any later day, would leak future information
    into a past score, and the research strand's day-by-day comparison against WHOOP Recovery is
    only honest if each score could have been computed on that morning.
  - `xcodebuild` on Xcode 27 would not resolve simulator destinations by name
    (`-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`); targeting by device UDID worked.
    Worth knowing before blaming the project spec.
  - Capture Quality thresholds are currently the model's own `usable` verdict; the numeric
    lighting/sharpness values are recorded and displayed but do not themselves gate a scan. If
    lighting turns out to dominate, that is the first knob to turn.

## 2) WHOOP Data Integration

- Date:
- OAuth/data retrieval steps implemented:
- Data fields collected:
- Result:
- Issues/observations:

## 3) Dataset Construction (Photos + WHOOP Recovery)

- Date:
- Photo source + curation steps:
- Pairing logic/criteria:
- Output dataset format/path:
- Issues/observations:

## 4) Initial LLM Recovery Scoring Baseline

- Date:
- Prompt used:
- Context/tooling used:
- Model:
- Output quality summary:
- Issues/observations:

## 5) Iteration Log (Prompt/Guidance/Tooling Improvements)

- Date:
- Change made:
- Why:
- Effect on output:
- Next step:
