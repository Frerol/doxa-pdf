# pdfium_ffi

Low-level Dart FFI bindings to [PDFium](https://pdfium.googlesource.com/pdfium/) and native library loading.
Only `doxa_engine` uses this package. Part of the [Doxa PDF](../../README.md) workspace; see
[PDF engine](../../docs/plan/04-pdf-engine.md).

## Native binaries
The binaries are **not committed**. `tools/fetch_pdfium.sh` downloads the release pinned in
[`tools/pdfium.lock`](../../tools/pdfium.lock) from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries)
(no V8, no XFA), verifies the SHA-256 and installs it into `third_party/pdfium/`:

| Path | Used by |
|---|---|
| `include/` | `tool/ffigen.dart` |
| `linux-x64/lib/libpdfium.so` | `dart test` on Linux (found automatically by `openPdfium()`) |
| `jniLibs/<abi>/libpdfium.so` | the Android build (`app/android/app/build.gradle.kts`) |
| `licenses/` | third-party notices (to be shown in the app's About screen) |

`openPdfium()` also honours `DOXA_PDFIUM_LIBRARY=/path/to/libpdfium.so`.

## Regenerating the bindings
`lib/src/pdfium_bindings.g.dart` is generated and committed. CI fails if it is out of date.

```sh
tools/fetch_pdfium.sh linux          # from the repository root
cd packages/pdfium_ffi
dart run tool/ffigen.dart            # needs libclang (Arch: clang; Ubuntu: libclang-dev)
```

The bound headers are listed in `tool/ffigen.dart`. Add a header there when a feature needs more of the API.

## Updating PDFium
1. Pick a release from bblanchon/pdfium-binaries and update `release`/`version` in `tools/pdfium.lock`.
2. Replace each checksum with the `sha256` digest GitHub shows for that asset.
3. `tools/fetch_pdfium.sh`, regenerate the bindings, then run `tools/check.sh`.
