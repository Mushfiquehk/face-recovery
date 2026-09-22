# The app calls the LLM directly; there is no backend

The obvious shape for a project with a research data pipeline is a server that holds the API key,
logs every request and later handles WHOOP OAuth. We are not building one. The app calls OpenRouter
directly and the key is entered once in Settings and stored in the iOS Keychain, never in the repo
or in a build configuration.

The reason is that the only user is the developer, on one device, and a server would double the
surface to build and debug while delaying the first on-device test by days. Provenance logging,
which is the main thing a server would have bought us, is achieved instead by recording the Scoring
Run on every scan and exporting it.

## Consequences

`.env` and `.env.example` are config for the Python training and dataset pipeline only; the iOS app
cannot and does not read them. Changing the prompt or the pinned provider requires an app rebuild.
If WHOOP OAuth is added later, this decision should be revisited, since a redirect URI and token
refresh are materially easier server-side.
