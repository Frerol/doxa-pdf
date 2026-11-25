# 07 — Build, Release & Distribution

## 1. Toolchain

- **Flutter** stable, pinned per release with [FVM](https://fvm.app) (`.fvmrc`). Dart pub **workspaces** for the monorepo.
- **PDFium** pinned by release tag + SHA-256 in `tools/pdfium.lock`.
- Android: JDK 17, Gradle wrapper, NDK pinned. Windows: Visual Studio 2022 Build Tools. Linux: clang, cmake, ninja, GTK 3 dev headers.
- Application ID: `io.github.frerol.doxapdf`. The Flathub naming rule for GitHub-hosted apps requires this reverse-DNS form, and it is reused on Android.

## 2. CI (GitHub Actions)

| Workflow | Trigger | Jobs |
|---|---|---|
| `ci.yml` | push, PR | format, analyze, unit/widget/golden tests (Linux); build debug for Android, Linux, Windows |
| `interop.yml` | PR touching `packages/doxa_engine` | round-trip + render comparison with pdf.js/MuPDF/Poppler |
| `nightly.yml` | schedule | integration tests (Android emulator, Linux, Windows), perf, fuzz |
| `release.yml` | tag `v*` | signed release builds, checksums, SBOM, GitHub Release draft |

Dependabot covers GitHub Actions, Gradle and pub. A scheduled job checks for new PDFium releases and opens a PR.

The M0 workflow publishes `lcov` for the Linux test suite, including the
native PDFium integration tests, and `android-debug-apk` for the Android
debug build. The Android job uses JDK 17 and installs the SDK platform and
NDK versions required by the Flutter SDK in `.fvmrc`. Update those Android
versions in the workflow when they change in Flutter.

The license checks read the resolved pub workspace and the Android debug
compile and runtime Gradle graphs, including transitive dependencies. The
pub check compares each external package's complete LICENSE, with whitespace
normalized, against the reviewed fingerprints in
[pub_licenses.tsv](../../tools/pub_licenses.tsv). Review changes to the license
text before adding a fingerprint. The Gradle check uses Maven license URLs and
explicit allowances for the pinned Flutter engine and the reviewed Guava
artifact with inherited license metadata. Missing or unrecognized license
metadata fails the check.

## 3. Packaging & channels

| Platform | Artifacts | Channels |
|---|---|---|
| Android | AAB (Play), per-ABI APKs | Google Play, **F-Droid** (built from source, including PDFium), GitHub Releases, Obtainium |
| Windows | MSIX + Inno Setup `.exe` + portable `.zip` | GitHub Releases, **winget**, (later) Microsoft Store |
| Linux | Flatpak, AppImage, `.deb`/`.rpm` (later) | **Flathub**, GitHub Releases, AUR (community) |

Platform notes:
- **Android**: Play requires a signing key. Use Play App Signing with an upload key held by the maintainer (CI keeps it in encrypted secrets). F-Droid signs its own builds.
- **Windows**: unsigned installers trigger SmartScreen. Plan for a code-signing certificate, or SignPath's free OSS program, before 1.0.
- **Linux**: the Flatpak needs portals for file access (no broad `--filesystem=home` by default) and an AppStream metainfo file with screenshots.

## 4. Versioning & release process

- **SemVer** (`MAJOR.MINOR.PATCH`), with `0.x` until 1.0. Android `versionCode` is derived from the version.
- **Conventional Commits** drive the changelog (`CHANGELOG.md`, Keep a Changelog format).
- Release flow: freeze, then a release candidate tag (`v0.3.0-rc.1`), then the manual checklist (stylus, interop, upgrade from previous version), then the final tag, then store submissions.
- Reproducibility: pinned toolchain plus lockfiles. Release artifacts ship with SHA-256 checksums and an SBOM (CycloneDX).
