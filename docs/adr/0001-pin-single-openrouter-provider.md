# Pin a single OpenRouter provider for scoring

The scoring model is `google/gemini-3.1-flash-lite`. On OpenRouter it is served by eight
endpoints across two providers, Google AI Studio and Google Vertex (global, EU and US regions,
each with flex and priority tiers). Under default routing the same photo could be scored by a
different endpoint on different days, and nothing in the stored data would record which. That
would quietly invalidate the reproducible Absolute Signals the research strand depends on.

We therefore pin `provider: { order: ["Google AI Studio"], allow_fallbacks: false }`, send a fixed
seed and a JSON schema, and record provider, model ID, seed, prompt version and schema version on
every Scoring Run. Google AI Studio supports `seed`, `temperature` and `structured_outputs` for
this model.

The scoring model was originally `z-ai/glm-5.3-flash`, served by 32 providers with inconsistent
`seed` and `structured_outputs` support. Scoring Runs recorded under that model are not comparable
with Gemini runs.

## Consequences

A provider outage fails the scan outright instead of silently rerouting. For a once-a-morning app
that is the correct failure mode, and the user can retry. Changing the pinned model or provider
later is a breaking change to the dataset and must be recorded as a new Scoring Run provenance
value, not applied retroactively.
