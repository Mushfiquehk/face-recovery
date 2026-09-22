# Score each photo in isolation, personalise in the app

Absolute facial appearance is dominated by whose face it is, not by how recovered they are: a user
with naturally dark under-eye circles would otherwise score in a narrow band forever and the app
would be useless. The obvious fix is to send a reference photo alongside today's and ask the model
to judge the change.

We rejected that. A comparative score depends on which reference happened to be used, so scores
become path-dependent, re-running an old scan gives a different answer, and the dataset stops being
reproducible. Instead the LLM always sees exactly one photo and rates Absolute Signals, and the app
converts them to deviations from a trailing 14-day per-Signal median before computing the Recovery
Score.

## Consequences

Personalisation is arithmetic over stored Absolute Signals, so changing the baseline window
recomputes the entire history instantly with no re-scoring cost. Users under three days of history
are Baseline Forming and see raw Absolute Signals. The model never gets the benefit of direct visual
comparison, which may cost sensitivity to subtle change.
