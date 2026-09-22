# Pin a single OpenRouter provider for scoring

Thirty-two providers serve `z-ai/glm-5.3-flash` on OpenRouter and they do not share capabilities:
several omit `seed`, several omit `structured_outputs`, and the first-party Z.AI endpoint omits
both. Under default routing the same photo could be scored by a different provider on different
days, with different quantisation and no determinism guarantees, and nothing in the stored data
would record which. That would quietly invalidate the reproducible Absolute Signals the research
strand depends on.

We therefore pin `provider: { order: ["DeepInfra"], allow_fallbacks: false }`, send a fixed seed
and a JSON schema, and record provider, model ID, seed, prompt version and schema version on every
Scoring Run.

## Consequences

A provider outage fails the scan outright instead of silently rerouting. For a once-a-morning app
that is the correct failure mode, and the user can retry. Changing the pinned provider later is a
breaking change to the dataset and must be recorded as a new Scoring Run provenance value, not
applied retroactively.
