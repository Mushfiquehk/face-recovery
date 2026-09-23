# v1 Implementation Plan

Scope, sequencing and concrete design for the first build that runs on a phone. Terms are used
exactly as defined in [`CONTEXT.md`](../CONTEXT.md); the non-obvious choices are justified in
[`docs/adr/`](./adr).

## 1. Scope

**In v1**

- Settings: OpenRouter API key entry, stored in the iOS Keychain
- Camera capture of a Face Scan, front camera, with a framing guide
- Backfill from the photo library, with EXIF dating and Date-Adjusted flagging
- Scoring via OpenRouter, pinned provider, fixed seed, JSON schema
- SwiftData persistence of Face Scans, Absolute Signals and Scoring Runs
- History list of Daily Recovery Scores
- Day detail: photo, Signals, Holistic Tiredness, Capture Quality, provenance
- Export of photos + JSON for the Python pipeline

**Explicitly out of v1**

- Insights and trend charts — they cannot be evaluated until real history exists, and Backfill
  is what creates it. They are the whole of v2.
- WHOOP integration and the dataset pairing pipeline
- Any comparative (two-photo) scoring — see ADR 0002

## 2. Prerequisites

1. `sudo xcode-select -s /Applications/Xcode.app` (currently points at Command Line Tools)
2. Sign into Xcode with a free Apple ID to create a Personal Team
3. `brew install xcodegen`
4. An OpenRouter API key, with account-level prompt-logging settings reviewed

## 3. Project setup

The project is generated from a checked-in `project.yml` via XcodeGen rather than committing an
`.xcodeproj`. Rationale: the build will be regenerated and re-signed constantly under the 7-day
Personal Team expiry, and a generated project keeps that reproducible and diff-free.

- Bundle ID: `com.mushfique.facerecovery`
- Deployment target: iOS 26
- SwiftUI lifecycle, no third-party dependencies
- Info.plist: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`

```
FaceRecovery/
├── App/                 FaceRecoveryApp.swift, RootView.swift
├── Model/               FaceScan, SignalSet, ScoringRun, CaptureQuality (SwiftData)
├── Scoring/             ScoringService, OpenRouterClient, ScoringSchema, Prompt
├── Analysis/            PersonalBaseline, RecoveryScoreCalculator
├── Capture/             CameraView, BackfillPicker, ExifReader
├── History/             HistoryListView, DayDetailView
├── Export/              ExportBuilder
└── Settings/            SettingsView, KeychainStore
```

## 4. Data model

```swift
@Model final class FaceScan {
    var id: UUID
    var capturedAt: Date          // from EXIF, or user-set
    var isDateAdjusted: Bool      // true when capturedAt did not come from EXIF
    var isBackfilled: Bool
    var photoFilename: String     // relative to Application Support/scans
    var isCanonical: Bool         // one per day; earliest by default
    var signals: SignalSet?
    var quality: CaptureQuality?
    var scoringRun: ScoringRun?
}

@Model final class SignalSet {        // Absolute Signals: raw, immutable, research-grade
    var underEyeDarkness: Int         // 0-100, higher = more pronounced fatigue marker
    var underEyePuffiness: Int
    var facialPuffiness: Int
    var eyeRedness: Int
    var skinDullness: Int
    var holisticTiredness: Int        // stored and baselined, NOT in the Recovery Score
}

@Model final class CaptureQuality {
    var lighting: Int                 // 0-100
    var faceFullyVisible: Bool
    var sharpness: Int                // 0-100
    var isUsable: Bool                // model's own verdict
}

@Model final class ScoringRun {
    var provider: String              // "Google AI Studio"
    var modelId: String               // "google/gemini-3.1-flash-lite"
    var seed: Int
    var promptVersion: String         // "v1"
    var schemaVersion: String         // "v1"
    var requestedAt: Date
    var rawResponseJSON: String       // kept verbatim for re-parsing later
}
```

Absolute Signals are never mutated after a Scoring Run. Everything personalised is derived at read
time, so retuning recomputes history with no re-scoring cost (ADR 0002).

## 5. Scoring

### Request

`POST https://openrouter.ai/api/v1/chat/completions`

```json
{
  "model": "google/gemini-3.1-flash-lite",
  "provider": { "order": ["Google AI Studio"], "allow_fallbacks": false },
  "seed": 42,
  "temperature": 0,
  "response_format": { "type": "json_schema", "json_schema": { "strict": true, "schema": { ... } } },
  "messages": [{ "role": "user", "content": [
      { "type": "text", "text": "<prompt v1>" },
      { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,..." } }
  ]}]
}
```

Images are downscaled to a 1024px long edge and JPEG-encoded at 0.8 before base64 encoding. At
roughly $0.0005 per scan this is immaterial to cost; it matters for upload time on cellular.

`allow_fallbacks: false` means a Google AI Studio outage fails the scan. That is deliberate (ADR 0001):
the UI surfaces a retry rather than silently producing a score from a different provider.

### Response schema (v1)

Six integers 0-100 (`under_eye_darkness`, `under_eye_puffiness`, `facial_puffiness`, `eye_redness`,
`skin_dullness`, `holistic_tiredness`) plus a `capture_quality` object (`lighting`, `sharpness`,
`face_fully_visible`, `usable`). All fields required, `additionalProperties: false`.

### Prompt v1

Rates only what is visible, states the direction of every scale explicitly (higher = more
pronounced), forbids inference about cause, sleep, health or lifestyle, and requires the capture
quality block to be filled honestly even when the face is unreadable. Stored as a versioned string
constant so `promptVersion` on every Scoring Run is meaningful.

## 6. Score computation

All derived, all recomputable:

```
baseline(s)   = median of signal s over the last 14 usable, non-Date-Adjusted Canonical Scans
deviation(s)  = absolute(s) - baseline(s)          // positive = worse than normal
meanDeviation = mean(deviation) over the FIVE observable Signals   // holistic excluded
RecoveryScore = clamp(0, 100, 70 - 1.5 * meanDeviation)
```

A day exactly at baseline scores 70. The constants 70 and 1.5 are an out-of-the-box starting point,
not a calibrated finding; they live in one struct and retuning them re-renders all history instantly.

**Baseline Forming** (fewer than 3 usable scans): `RecoveryScore = 100 - mean(five Signals)`, shown
with a "baseline forming" label so an early number is never mistaken for a personalised one.

**Unusable Scans** are stored and displayed but excluded from baselines and from the history trend.

## 7. Screens

1. **Settings** — API key field (masked, Keychain-backed), a "test connection" call, and a read-only
   display of pinned model/provider/seed so provenance is visible without reading code.
2. **Capture** — front camera, oval framing guide, capture, then an immediate scoring call with a
   progress state and an explicit retry on failure.
3. **Backfill** — photo picker, EXIF capture date pre-filled and editable, a visible warning that
   editing marks the scan Date-Adjusted and excludes it from research exports.
4. **History** — reverse-chronological Daily Recovery Scores, days with no scan shown as gaps rather
   than interpolated, Unusable Scans visibly marked.
5. **Day detail** — photo, the five Signals with their deviation from baseline, Holistic Tiredness
   shown separately and labelled as excluded from the score, Capture Quality, and full provenance.
   If the day has multiple scans, all are listed and the Canonical one can be re-designated.
6. **Export** — writes `export-<date>/` containing `scans.json` and the photo files, handed to the
   share sheet.

## 8. Export format

`scans.json` is an array of records, each carrying the scan, its Absolute Signals, Capture Quality
and full Scoring Run, with `photo` naming a file in the same folder. Derived values (Recovery Score,
baselines) are deliberately NOT exported — the pipeline recomputes them so the app and the analysis
can never disagree about how a score was produced.

## 9. Sequencing

Each step ends at something runnable on the phone.

| Step | Delivers | Done when |
|---|---|---|
| 1 | XcodeGen project, app target, signing | Blank app launches on the device |
| 2 | Settings + Keychain + connection test | Key persists across a relaunch |
| 3 | `ScoringService` + schema + prompt v1 | A bundled test photo returns a parsed `SignalSet` |
| 4 | Camera capture wired to scoring | Photograph yourself, see six Signals on screen |
| 5 | SwiftData persistence + photo storage | Scans survive a relaunch |
| 6 | Backfill with EXIF dating | Three weeks of camera-roll photos scored and dated |
| 7 | Baseline + Recovery Score + History | History shows Daily Recovery Scores, gaps are gaps |
| 8 | Day detail + Canonical re-designation | Multi-scan days behave correctly |
| 9 | Export | `scans.json` opens in Python and round-trips |

Step 6 is the point at which the app becomes worth using daily: backfill creates the history that
makes baselining meaningful on the first day rather than the fifteenth.

## 10. Validation before trusting any number

1. **Noise floor.** Take three scans back to back on one morning. The spread across them is the
   smallest change that can mean anything. If it is ±10, a 6-point day-to-day move is noise.
2. **Lighting sensitivity.** Scan the same face in three different lights within ten minutes. If the
   Signals move more than they do across a bad night versus a good one, capture conditions dominate
   the measurement and the protocol needs fixing before the data is worth collecting.
3. **Seed determinism.** Re-score one stored photo twice and confirm identical Signals. If not, the
   pinned provider is not honouring the seed and ADR 0001 needs revisiting.

## 11. Known risks

- **Lighting is the dominant confound.** Capture Quality gates the worst cases but not systematic
  drift; darker winter mornings will read as a downward recovery trend. A fixed location and time of
  day is worth more than any prompt tuning.
- **Personal Team expiry.** Builds die after 7 days. Export is the only backup; there is no iCloud
  on this tier.
- **GLM 5.3 Flash is unvalidated for this task.** Step 4 is the real go/no-go. If Signals do not
  move sensibly with obvious inputs, no amount of downstream machinery helps.
- **OpenRouter data handling for face photographs** is unverified and needs settling at the account
  level before real scans, and a sentence in the report either way.
