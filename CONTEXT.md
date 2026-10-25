# Face Recovery

A personal sleep-tracking app: a morning face photo is measured on the device, and those
measurements predict the user's WHOOP Sleep Performance, with every point of the prediction traced
back to a visible facial characteristic. A research strand pairs the same photos with WHOOP data to
fit and test that prediction.

## Language

### Prediction

**Face Scan**:
A single photo of the user's face, together with the date and time it was captured, measured on
the device. Scans are never overwritten or deleted.
_Avoid_: selfie, capture, image, upload

**Signal**:
One directly observable facial characteristic measured on the device from a Face Scan, such as how
open the eyelids are or how much darker the skin under the eyes is than the cheek. A Signal is an
observation, never an inference about cause.
_Avoid_: sub-score, feature, metric, dimension

**Sleep Prediction**:
A 0-100 estimate, from one Face Scan, of the WHOOP Sleep Performance for the night before it. It is
the Sleep Model's starting value plus one Contribution per Signal, so every point is accounted for.
_Avoid_: sleep score, recovery score, readiness

**Contribution**:
How many points one Signal moved a Sleep Prediction, given how far that Signal was from the user's
Personal Baseline. The Contributions of a scan are its explanation.
_Avoid_: reason, factor, impact, attribution

**Daily Sleep Prediction**:
The Sleep Prediction of a day's Canonical Scan. This is the number shown in the history and used for
trends. A day with no Face Scan has no Daily Sleep Prediction.
_Avoid_: daily score, today's sleep

**Canonical Scan**:
The one Face Scan that represents a given day. Defaults to the earliest scan of that day; the user
may re-designate another, and that re-designation is recorded.
_Avoid_: primary scan, main photo, selected scan

**Sleep Model**:
The starting value and per-Signal weights that turn a scan's Signals into a Sleep Prediction. It is
fitted to the user's own WHOOP Sleep Performance, anchored to published facial cues of sleep loss
while there are few nights, and every Sleep Prediction records the Sleep Model version behind it.
_Avoid_: algorithm, AI, weights, classifier

**WHOOP Sleep Performance**:
WHOOP's 0-100 percentage of the sleep the user needed that they actually got, for the main sleep
before a Face Scan. It is what the Sleep Model is fitted to and what a Sleep Prediction estimates;
it is never copied into a Sleep Prediction.
_Avoid_: sleep score, sleep quality

**WHOOP Recovery**:
The 0-100 readiness percentage produced by WHOOP from HRV, resting heart rate and sleep. A research
ground truth only: it is never shown as, or blended into, a Sleep Prediction.
_Avoid_: recovery score, recovery percentage

### Baselining

**Absolute Signals**:
The Signals measured from a Face Scan photo alone, with no reference image and no history. Measuring
is deterministic, so the same photo and Measurement Version always give the same Absolute Signals.
_Avoid_: raw scores, unadjusted signals

**Personal Baseline**:
The trailing 14-day median of each Absolute Signal for this user, representing what their face
normally looks like. Recomputable from stored Absolute Signals at any time.
_Avoid_: normal, reference, average face

**Measurement Version**:
The version of the on-device measurement that produced a scan's Absolute Signals and Capture
Quality. Photos are kept, so a new Measurement Version re-measures every past Face Scan rather than
mixing versions.
_Avoid_: model version, scoring version

**Baseline Forming**:
The state of a user with fewer than three days of history, where no meaningful Personal Baseline
exists yet and every Sleep Prediction is marked as provisional.
_Avoid_: cold start, onboarding period

**LLM Signals**:
The 0-100 ratings an image LLM gave earlier Face Scans (including its overall Holistic Tiredness),
each recorded with the Scoring Run that produced it. Kept on those scans and in exports; no new
scan gets them and they never feed a Sleep Prediction.
_Avoid_: old signals, legacy scores

### Capture

**Capture Quality**:
The device's assessment of the photograph rather than the face in it: lighting and its colour,
sharpness, whether the whole face is visible and facing the camera, and whether glasses are off.
Scans are always taken without glasses. Measured on every Face Scan.
_Avoid_: image quality, validity, confidence

**Unusable Scan**:
A Face Scan whose Capture Quality falls below threshold. It is stored in full but gets no Sleep
Prediction and is excluded from the Personal Baseline and from trends, so that lighting or framing
cannot be mistaken for a bad night.
_Avoid_: rejected scan, invalid scan, failed scan

### Provenance

**Backfill**:
Submitting a Face Scan for a past day from an existing photo, rather than capturing it live.
_Avoid_: import, retro-upload, historical entry

**Date-Adjusted**:
A permanent mark on a Face Scan whose date was set by the user rather than read from the photo's
EXIF capture timestamp. Date-Adjusted scans are excluded from research datasets by default.
_Avoid_: manual date, edited date

### Self-report

**Journal Entry**:
The user's own account of one day: Perceived Recovery, how they slept, the medicines they took,
anything else from the day before, and free notes. At most one per day, matched to that day's Face
Scans by date. It never changes a Sleep Prediction.
_Avoid_: diary, log, check-in, survey, note

**Perceived Recovery**:
How recovered the user says they feel, on a five-point scale from Exhausted to Great, recorded in a
Journal Entry. It is kept apart from the Sleep Prediction (what the face suggests) and from WHOOP
(what the body measures), so that the three can be compared.
_Avoid_: mood, feeling score, subjective recovery, self-score

**Blind to Score**:
A Journal Entry answered before any Sleep Prediction for its day was shown, so the answers cannot
have been anchored by the number. Only an entry written straight after the shutter is Blind to
Score; any later edit permanently clears it.
_Avoid_: unbiased, pre-score

### Interpretation

**Insight**:
A statement the app derives arithmetically from stored Signals, Contributions and Sleep Predictions,
such as a deviation from Personal Baseline or a trend over a window. Insights describe what was
observed and never assert a physiological cause or give health advice.
_Avoid_: recommendation, advice, analysis, coaching

### Sharing

**Family Update**:
A short first-person text about today (the Daily Sleep Prediction and chosen Journal Entry
answers) that the user's own Shortcuts automation sends to family or a friend. Off until turned
on; never includes photos or notes (ADR 0006).
_Avoid_: report, alert, notification, share
