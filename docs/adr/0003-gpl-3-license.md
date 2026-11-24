# ADR-0003 — GPL-3.0-or-later as the project license

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
The project should stay free software, including forks and redistributed builds.

## Decision
License all project code under **GPL-3.0-or-later**. Contributions are accepted under the DCO.

## Consequences
- Forks and redistributed binaries must provide source under the same terms.
- Dependencies must be GPL-3.0-compatible (MIT, BSD, Apache-2.0, LGPL, MPL-2.0, GPL-3.0); checked in CI.
- Distribution through Google Play, F-Droid, Flathub and winget remains possible.

## Alternatives considered
- **Apache-2.0/MIT**: maximizes reuse, but allows proprietary forks.
- **AGPL-3.0**: only needed if we used MuPDF; its network clause adds nothing for a local app.
