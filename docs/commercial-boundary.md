# Commercial Boundary

Symaira Terminal is free and open source under the AGPLv3.

The public repository contains the complete macOS application: the terminal engine
integration, agent status system, git worktree isolation, context bank, and the full
BYOK (bring-your-own-key) AI integration. Everything a user needs to download their
own build, add their own API keys, and work — with no account and no Symaira
services involved — lives here and stays free.

Commercial hosted-service code lives outside this repository. That private Pro layer
(`symaira-terminal-pro`) may provide team features that inherently require servers:
mobile companion sync relay (E2EE), hosted localhost tunnels, commit-context sharing
across a team, workspace cloud sync, billing, and tenant operations.

## Rules

- Keep the full local product — including BYOK — free and AGPLv3-licensed in this
  repository.
- Do not require private code to build, test, or run the public app.
- Do not copy private Pro code into the public repository.
- Do not copy public internal sources into the private Pro repository.
- When the hosted service needs a new core capability (e.g. the client side of an
  E2EE sync protocol), implement and release it publicly here first, then let the
  private Pro repository consume the tagged artifact.

## License Note

The other Symaira cores are MIT-licensed; the terminal deliberately uses AGPLv3.
Rationale: the terminal is an end-user application (not a library/CLI building
block), and AGPLv3 ensures that distributed forks of the app remain open while the
copyright holder can still offer proprietary cloud services on top (open-core).
Embedded MIT-licensed code (libghostty/GhosttyKit) is compatible with AGPLv3.
