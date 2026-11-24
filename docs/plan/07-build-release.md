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
