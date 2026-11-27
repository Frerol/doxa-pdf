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
- **Windows**: unsigned installers trigger SmartScreen. Plan for a code-signing certificate, or SignPath's free OSS program, before the Windows release (1.2.0).
- **Linux**: the Flatpak needs portals for file access (no broad `--filesystem=home` by default) and an AppStream metainfo file with screenshots.

## 4. Versioning & release process

- **SemVer** (`MAJOR.MINOR.PATCH`). Decided with the maintainer on 2026-11-26. Until the first stable release, every release is a **pre-release of 1.0.0**:

  | Stage | Versions | Meaning |
  |---|---|---|
  | Alpha | `1.0.0-alpha.1` … `1.0.0-alpha.4` | Early development: incomplete features, may be unstable. One alpha per MVP milestone (M1–M4, [roadmap](08-roadmap.md)); fixes to an alpha are `1.0.0-alpha.1.1`, `alpha.1.2`… |
  | Beta | `1.0.0-beta.1`, `beta.2`… | Every MVP feature is in; testing and fixes only |
  | Release candidate | `1.0.0-rc.1`, `rc.2`… | Candidate for release, no known critical (S1) problems |
  | Stable | `1.0.0` | First official release |

- **After 1.0.0**, each number has one purpose: **MAJOR** for incompatible changes (for example a change in how annotations are stored that older versions cannot read),
  **MINOR** for new compatible features (Linux is 1.1.0, Windows 1.2.0), **PATCH** for bug fixes only (1.0.1, 1.0.2…).
- Git tags are `v` + the version (`v1.0.0-alpha.1`). Alphas, betas and release candidates are marked **pre-release** on GitHub Releases.
- Android `versionCode` is derived from the version and MUST grow with every release, in SemVer order:
  `MAJOR × 10 000 000 + MINOR × 100 000 + PATCH × 1 000 + stage`, where stage is `100 + 10 × N + F` for `alpha.N.F` (`F` = 0 without a fix number; N, F ≤ 9),
  `300 + N` for `beta.N`, `500 + N` for `rc.N`, and `999` for the final release. For example, `1.0.0-alpha.1` is 10 000 110, `1.0.0-alpha.1.2` is 10 000 112 and `1.0.0` is 10 000 999.
  `tools/version_code.py` computes it; the pubspec build number MUST equal it (`app/pubspec.yaml` `version: 1.0.0-alpha.1+10000110`, checked in CI).
  All per-ABI APKs share the same code (`force-version-code-ignoring-abi`), because Flutter's ABI × 1000 offset would collide with the PATCH digits.
- **Conventional Commits** drive the changelog (`CHANGELOG.md`, Keep a Changelog format).
- **Release workflow** (`.github/workflows/release.yml`, on `v*` tags): checks that the tag names the app version, builds signed per-ABI APKs
  (`arm64-v8a`, `armeabi-v7a`, `x86_64`), checks each one's signer, `versionCode` and `versionName`, checks the release dependency licenses, writes a CycloneDX SBOM
  (`tools/generate_sbom.py`) and `SHA256SUMS`, and creates a **draft** release,
  marked pre-release when the version has a `-` suffix. The release key comes from the secrets `DOXA_RELEASE_KEYSTORE_BASE64`, `DOXA_RELEASE_STORE_PASSWORD`,
  `DOXA_RELEASE_KEY_ALIAS` and `DOXA_RELEASE_KEY_PASSWORD`; local release builds without them are signed with the debug key.
- Release flow for alphas and betas: tag, signed release draft, the manual checklist on the reference tablet (stylus, interop, upgrade from the previous version), then publish.
  For 1.0.0 and every later minor or major release: freeze, release candidates (`v1.1.0-rc.1`…) until one passes the checklist, then the final tag, then store submissions.
- Reproducibility: pinned toolchain plus lockfiles. Release artifacts ship with SHA-256 checksums and an SBOM (CycloneDX).
