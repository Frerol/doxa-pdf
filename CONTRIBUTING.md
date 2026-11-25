# Contributing to Doxa PDF

Thanks for your interest! Doxa PDF is in **early development** (Android MVP). The most valuable contributions right now are
feedback on the [engineering plan](docs/README.md) and help with the [M1 issues](https://github.com/Frerol/doxa-pdf/milestone/2) (v0.1 Reader).

## Ground rules
- Read the [Code of Conduct](CODE_OF_CONDUCT.md).
- Discuss larger changes in an issue first. Significant decisions need an [ADR](docs/adr/0000-template.md).
- Keep the study focus in mind: see [Vision & Scope](docs/plan/01-vision-and-scope.md#5-feature-priorities).
- Never copy code, assets or text from proprietary PDF apps.

## Workflow
1. Fork and create a branch: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>` or `spike/<topic>`.
2. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat(ink): …`, `fix(engine): …`).
3. Sign off every commit (DCO): `git commit -s`.
4. Reference requirement IDs (`FR-…`/`NFR-…`) and issues in your PR.
5. Make sure CI is green: format, analyze, tests.

## Developer Certificate of Origin
By signing off a commit you certify the [DCO 1.1](https://developercertificate.org/): you wrote the change or have the right to submit it
under the project's license (GPL-3.0-or-later).

## Setting up a development environment

The MVP targets **Android** (minSdk 29). You need:

| Tool | Version | Notes |
|---|---|---|
| [FVM](https://fvm.app) | 4.x | Installs the Flutter version pinned in `.fvmrc` |
| Flutter | pinned in `.fvmrc` | `fvm install` in the repo root |
| JDK | 17 | e.g. Eclipse Temurin; set `JAVA_HOME` |
| Android SDK | platform 36, build-tools 36 | set `ANDROID_HOME`; accept licenses with `sdkmanager --licenses` |

```sh
fvm install                 # install the pinned Flutter
tools/fetch_pdfium.sh       # download the pinned PDFium binaries (Linux + Android)
fvm flutter pub get         # resolve the whole pub workspace (app + packages)
tools/check.sh              # format, analyze and test everything (same as CI)
cd app && fvm flutter run   # run on a connected Android device or emulator
```

### Repository layout
The repo is a [pub workspace](docs/adr/0004-monorepo-with-pub-workspaces.md): the Flutter app is in `app/`, and libraries
are in `packages/` (`doxa_core`, `doxa_ink`, `doxa_engine`, `pdfium_ffi`, `doxa_platform`). Pure Dart packages are tested
with `dart test`; Flutter ones with `flutter test`.

### Conventions
- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Import Material from `package:material_ui/material_ui.dart` (`package:flutter/material.dart` is deprecated since Flutter 3.47).
- UI strings live in `app/lib/l10n/app_en.arb` and `app_pt.arb`; both must be updated together.
