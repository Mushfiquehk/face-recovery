# Pin a single OpenRouter provider for scoring

The scoring model is `nvidia/nemotron-3.5-super-vl:free`, an open multimodal model that costs
nothing to call. On OpenRouter it has a single endpoint, served by Nvidia. It is the only free
vision model there that supports both `seed` and `structured_outputs`, which the reproducible
Absolute Signals the research strand depends on require.

Pinning still matters in principle: under default routing a model with several endpoints could
score the same photo differently on different days, and nothing in the stored data would record
which. We therefore pin `provider: { order: ["Nvidia"], allow_fallbacks: false }`, send a fixed
seed and a JSON schema, and record provider, model ID, seed, prompt version and schema version on
every Scoring Run.

Scoring Runs recorded under earlier models are not comparable with these. The history is:
`z-ai/glm-5.3-flash` (32 providers with inconsistent `seed` and `structured_outputs` support;
CoreWeave rate-limited it with 429s), then `google/gemini-3.1-flash-lite` on Google AI Studio,
then this model.

## Consequences

A provider outage fails the scan instead of silently rerouting. Free endpoints rate-limit and
drop requests more often than paid ones, so the client retries 429 and 5xx responses twice
(after 3 and 8 seconds) before surfacing an error. The request is identical on each attempt, so a
retry cannot change the Signals. If it still fails the photo is already saved and the user can
retry by hand. The model is also a reasoning model, so a scan takes roughly 7-40 seconds.

Changing the pinned model or provider later is a breaking change to the dataset and must be
recorded as a new Scoring Run provenance value, not applied retroactively.
