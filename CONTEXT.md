# Face Recovery

A personal recovery-tracking app: a morning face photo is scored by an image LLM, and the daily
history of those scores is used to give the user insight into their recovery. A separate research
strand pairs the same photos with WHOOP data to test whether facial appearance predicts recovery.

## Language

### Scoring

**Face Scan**:
A single photo of the user's face submitted for scoring, together with the date and time it was
captured. Scans are never overwritten or deleted.
_Avoid_: selfie, capture, image, upload

**Signal**:
One directly observable facial characteristic the LLM rates 0-100 for a Face Scan. There are five:
under-eye darkness, under-eye puffiness, overall facial puffiness, eye redness, and skin dullness.
A Signal is an observation, never an inference about cause.
_Avoid_: sub-score, feature, metric, dimension

**Holistic Tiredness**:
The LLM's overall impression, 0-100, of how tired a face looks. It is rated, baselined and stored
on every Face Scan but is deliberately excluded from the Recovery Score, so that the decomposed
Signals and the holistic judgement can be tested against WHOOP Recovery independently.
_Avoid_: overall score, fatigue score, tiredness signal

**Recovery Score**:
A 0-100 assessment of how recovered or fatigued a face *looks* in one Face Scan, computed by the
app from that scan's Signals measured against the user's Personal Baseline. It is a judgement about
visible appearance only, deliberately independent of any physiological measurement.
_Avoid_: recovery %, readiness, sleep score

**Daily Recovery Score**:
The Recovery Score of a day's Canonical Scan. This is the number shown in the history and used for
trends. A day with no Face Scan has no Daily Recovery Score.
_Avoid_: daily score, today's recovery

**Canonical Scan**:
The one Face Scan that represents a given day. Defaults to the earliest scan of that day; the user
may re-designate another, and that re-designation is recorded.
_Avoid_: primary scan, main photo, selected scan

**WHOOP Recovery**:
The 0-100 readiness percentage produced by WHOOP from HRV, resting heart rate and sleep. It is
ground truth for the research strand and is never shown as, or blended into, a Recovery Score.
_Avoid_: recovery score, recovery percentage

### Baselining

**Absolute Signals**:
The Signal ratings the LLM produces from a Face Scan photo alone, with no reference image and no
history in the prompt. Every scan has exactly one set, they never change, and they are the only
data the research strand uses.
_Avoid_: raw scores, unadjusted signals

**Personal Baseline**:
The trailing 14-day median of each Absolute Signal for this user, representing what their face
normally looks like. Recomputable from stored Absolute Signals at any time.
_Avoid_: normal, reference, average face

**Scoring Run**:
One invocation of the LLM against one Face Scan, recorded with the provider, model ID, seed, prompt
version and schema version that produced it. A scan's Absolute Signals are meaningless without the
Scoring Run that generated them.
_Avoid_: request, inference, API call

**Baseline Forming**:
The state of a user with fewer than three days of history, where no meaningful Personal Baseline
exists yet and the app shows Absolute Signals directly.
_Avoid_: cold start, onboarding period

### Capture

**Capture Quality**:
The LLM's assessment of the photograph itself rather than the face in it: lighting adequacy, whether
the face is fully visible, and sharpness. Rated on every Face Scan.
_Avoid_: image quality, validity, confidence

**Unusable Scan**:
A Face Scan whose Capture Quality falls below threshold. It is stored in full but excluded from the
Personal Baseline and from trends, so that lighting or framing cannot be mistaken for recovery.
_Avoid_: rejected scan, invalid scan, failed scan

### Provenance

**Backfill**:
Submitting a Face Scan for a past day from an existing photo, rather than capturing it live.
_Avoid_: import, retro-upload, historical entry

**Date-Adjusted**:
A permanent mark on a Face Scan whose date was set by the user rather than read from the photo's
EXIF capture timestamp. Date-Adjusted scans are excluded from research datasets by default.
_Avoid_: manual date, edited date

### Interpretation

**Insight**:
A statement the app derives arithmetically from stored Signals and Recovery Scores, such as a
deviation from Personal Baseline or a trend over a window. Insights describe what was observed and
never assert a physiological cause or give health advice.
_Avoid_: recommendation, advice, analysis, coaching
