# Measure the face on the device and predict WHOOP Sleep Performance

Supersedes the Recovery Score of ADR 0002 and the LLM call of ADRs 0001 and 0003; Personal
Baseline arithmetic from ADR 0002 stays.

The app's headline number is now a Sleep Prediction: an estimate of the user's WHOOP Sleep
Performance from Signals that Apple Vision and plain pixel arithmetic measure on the phone. It is
a fixed starting value plus one weight per Signal deviation from the Personal Baseline, so each
Signal's Contribution is exact and can be shown to the user. The weights are fitted on the Mac to
the user's own WHOOP history and shipped in the app as a versioned Sleep Model.

We chose this over keeping an image LLM because an LLM rating cannot be decomposed into reasons,
costs a network round trip and an API key, and was not reproducible across providers. We chose
fitting to WHOOP over a pure "looks recovered" score because the user wants the number to mean
something measurable. We chose Apple Vision over a bundled landmark model (MediaPipe) because it
adds no dependency or download and the same Swift measurement code runs on the Mac for research,
so research and app can never measure differently.

## Consequences

With few nights a free fit is noise, so weights are anchored to published facial cues of sleep loss
(eyelid opening, under-eye shadow, eye redness, skin paleness) and only move as far as the data
supports. WHOOP Sleep Performance now shapes the number, so it is no longer an independent check
on it: the research strand must evaluate each Sleep Model on nights it was not fitted to. WHOOP
Recovery stays out entirely. A new Measurement Version re-measures every stored photo instead of
mixing versions; LLM Signals already stored are kept for history and export but never feed a Sleep
Prediction.
