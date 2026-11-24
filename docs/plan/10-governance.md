# 10 — Governance & Workflow

## 1. Decision making
- The maintainer decides, after discussion in issues or PRs. A significant or hard-to-reverse decision needs an **ADR** in `docs/adr/` (start from [the template](../adr/0000-template.md)).
- A new feature area outside the [current tiers](01-vision-and-scope.md#5-feature-priorities) needs an ADR before code.

## 2. Git workflow
- `main` is always releasable and protected: PR + green CI required.
- Branches: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>`, `spike/<topic>`.
- **Conventional Commits** (`feat(ink): add pressure curve setting`). Squash merge.
- PRs reference requirement IDs (`FR-…`, `NFR-…`) and issues.

## 3. Issue tracking
- Labels: `type:{bug,feature,docs,chore,spike}`, `area:{reader,markup,ink,notes,review,library,engine,platform,build}`, `platform:{android,windows,linux}`, `severity:{s1..s4}`, `good first issue`, `help wanted`.
- One GitHub milestone per roadmap milestone (M0–M4).
- A GitHub Project board: Backlog → Ready → In progress → Review → Done.

## 4. Licensing hygiene
- Project license: **GPL-3.0-or-later** ([ADR-0003](../adr/0003-gpl-3-license.md)). Source files carry an SPDX header: `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Dependencies must be GPL-3.0-compatible (MIT, BSD, Apache-2.0, LGPL, MPL-2.0, GPL-3.0). A CI license check over pub, Gradle and native deps blocks anything else.
- Contributions use the **DCO** (`Signed-off-by:` line), not a CLA.
- Test corpus files need a recorded license and source.
- `NOTICE`/about screen lists third-party licenses (Flutter `LicenseRegistry` + PDFium license).

## 5. Community
- [CONTRIBUTING.md](../../CONTRIBUTING.md), [CODE_OF_CONDUCT.md](../../CODE_OF_CONDUCT.md), [SECURITY.md](../../SECURITY.md).
- GitHub Discussions for questions and ideas. Issues are for actionable bugs and features.
- Translations: ARB files in the repo first; a hosted platform (for example Weblate's free libre plan) once strings stabilize.
