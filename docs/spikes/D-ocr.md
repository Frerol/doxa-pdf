# Spike D — On-device OCR

**Issue #8 · Draft · Linux host results.** PDFium preserved the page images and
made the OCR text selectable on both fixtures. The Android integration and the
Galaxy Tab S10 FE performance decision are pending. This spike covers
FR-UTIL-001 and NFR-PERF-009 for v0.4.

## Android integration options

All three paths can use the same Apache-2.0
[tessdata_fast 4.1.0 models](https://github.com/tesseract-ocr/tessdata_fast/tree/4.1.0).
The host downloads were 1,982,756 bytes for Portuguese and 4,113,088 bytes for
English (6,095,844 bytes total, 5.81 MiB). Supply no language assets in the APK.
On the first explicit OCR request, offer to download the selected languages over
HTTPS to private storage. Pin the URLs and hashes below, verify the temporary
files, and rename them into `tessdata/` after verification. Initialize with
`por+eng` and LSTM mode for the bilingual run. Subsequent OCR can run offline.
The tested page segmentation mode (PSM 3) needs no OSD model.

| Route | Maintenance and ABI support | Estimated APK delta per ABI, excluding models |
| --- | --- | --- |
| Tesseract4Android standard via a small Kotlin platform channel | Upstream 4.9.0 ships Tesseract 5.5.1 and updated libpng. The tagged Gradle configuration builds for all NDK ABIs, including arm64-v8a, armeabi-v7a and x86_64. Java exposes word results through the iterator and cooperative cancellation through `stop()`. Confirm the actual AAR contents before adoption. [Release](https://github.com/adaptech-cz/Tesseract4Android/releases/tag/4.9.0) · [Build](https://github.com/adaptech-cz/Tesseract4Android/blob/4.9.0/tesseract4android/build.gradle) · [API](https://github.com/adaptech-cz/Tesseract4Android/blob/4.9.0/tesseract4android/src/main/java/com/googlecode/tesseract/android/TessBaseAPI.java) | Roughly 4–6 MiB if deflated, 8–11 MiB if stored. |
| Build Tesseract + Leptonica with the NDK and call the C API from Dart FFI | Active native upstreams with tagged Tesseract 5.5.4 and Leptonica 1.87.0. Doxa owns the bindings, builds, upgrades and runtime checks for arm64-v8a, armeabi-v7a and x86_64. Pass PDFium grayscale raster bytes directly and use the result iterator for word boxes. A separate OCR worker and a cancellation monitor keep a synchronous FFI call off the UI and PDFium isolates. [Tesseract releases](https://github.com/tesseract-ocr/tesseract/releases) · [Leptonica releases](https://github.com/DanBloomberg/leptonica/releases) · [C API](https://github.com/tesseract-ocr/tesseract/blob/5.5.4/include/tesseract/capi.h) · [NDK ABIs](https://developer.android.com/ndk/guides/abis) | Roughly 3–5 MiB if deflated, 7–10 MiB if stored. |
| NDK-built Tesseract CLI subprocess | Same active native upstreams and the same three NDK build targets. Doxa owns executable packaging, lifecycle and upgrades. Offline PGM → TSV mirrors the host spike. The subprocess can be terminated independently. Android 10+ restricts executing binaries from writable app home, so APK-installed executable packaging and launch must be proven on Android. [Tesseract build documentation](https://github.com/tesseract-ocr/tessdoc/blob/main/Compiling.md) · [Android execution restrictions](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission) | Roughly 3–6 MiB if deflated, 7–11 MiB if stored with a single stripped binary. |

> **To verify before ADR-0007:** the versions, licenses and APK size ranges in this section were compiled during the spike
> and have not yet been checked against the upstream sources linked here.

These are planning estimates for each of the three split APKs, not measurements
of Android artifacts. The x86_64 Linux Tesseract + Leptonica libraries total
7.60 MiB raw and 3.61 MiB deflated. Adding the host JPEG and PNG libraries gives
8.59 MiB raw and 3.99 MiB deflated. The ranges allow for architecture, C++
runtime, linker settings and the Java/JNI or CLI layer. APK storage and
alignment settings determine the actual on-disk delta.

- **Tesseract4Android standard** uses Apache-2.0 for the wrapper, Tesseract and
  AndroidX Annotation. Leptonica 1.85.0 uses BSD-2-Clause, libjpeg v9f uses IJG
  terms, libpng 1.6.48 uses libpng-2.0 (legacy pieces under libpng terms),
  and the PNG build links to platform zlib (Zlib). The standard variant
  avoids an OpenMP runtime. Account for NDK libc++ notices (Apache-2.0 with LLVM
  exceptions, or the applicable legacy dual-license terms) when redistributing.
  [Tagged dependency list](https://github.com/adaptech-cz/Tesseract4Android/blob/4.9.0/README.md) ·
  [Native build](https://github.com/adaptech-cz/Tesseract4Android/tree/4.9.0/tesseract4android/src/main/cpp) ·
  [IJG](https://www.ijg.org/files/README) ·
  [libpng](https://github.com/pnggroup/libpng/blob/v1.6.48/LICENSE) ·
  [zlib](https://zlib.net/zlib_license.html) ·
  [LLVM runtime terms](https://github.com/llvm/llvm-project/blob/main/libcxx/LICENSE.TXT)
- **Minimal FFI and CLI builds** use Apache-2.0 Tesseract, BSD-2-Clause
  Leptonica, the same NDK runtime terms, and Doxa's GPL-3.0-or-later integration.
  Raw grayscale (FFI) and PGM (CLI) allow disabling optional image codecs,
  archive/curl support, training tools and OpenMP. Confirm linked libraries
  and transitive notices against the actual build before distribution.
  [Tesseract license](https://github.com/tesseract-ocr/tesseract/blob/5.5.4/LICENSE) ·
  [Leptonica license](https://github.com/DanBloomberg/leptonica/blob/1.87.0/leptonica-license.txt) ·
  [Leptonica build options](https://github.com/DanBloomberg/leptonica/blob/1.87.0/CMakeLists.txt) ·
  [Tesseract input formats](https://github.com/tesseract-ocr/tessdoc/blob/main/InputFormats.md)

The standard Tesseract4Android build is the first candidate for the tablet
trial. It provides the native iterator and stop hook without owning a new
native toolchain. The FFI build offers reuse on desktop and tighter control
over the binary and raster buffers. The CLI is useful for reproducing the
host flow, with additional process and packaging costs. These are candidates
for testing. The tablet results determine go/no-go.

## Linux method and reproduction

The standalone Dart package uses the existing `pdfium_ffi` and `ffi`
dependencies. From the repository root, with FVM's Dart on PATH:

```sh
tools/fetch_pdfium.sh linux
tools/fetch_corpus.sh
cd spikes/ocr_lab
dart pub get
mkdir -p out/tessdata
for lang in por eng; do
  curl --fail --location \
    "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/$lang.traineddata" \
    --output "out/tessdata/$lang.traineddata" || exit
done
sha256sum --check <<'SUMS'
c4932b937207a9514b7514d518b931a99938c02a28a5a5a553f8599ed58b7deb  out/tessdata/por.traineddata
7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2  out/tessdata/eng.traineddata
SUMS
dart format --output=none --set-exit-if-changed bin
dart analyze
python3 benchmark.py ../../test_corpus/scanned-300.pdf 1
python3 benchmark.py ../../test_corpus/external/scanned-chapter.pdf 1 2 3
```

The driver uses Poppler (`pdftoppm`) to rasterize each requested page as a
300 dpi grayscale PGM, then starts Tesseract three times on that raster.
Tesseract runs with `OMP_THREAD_LIMIT=1`, `por+eng`, OEM 1 and PSM 3, and
emits TSV to stdout. The timing includes CLI startup and loading both models.
Linux `wait4` reports each process's peak RSS. The Dart writer runs separately
from Poppler and Tesseract. Output copies, downloaded models and intermediate
rasters/TSVs are all under the ignored `spikes/ocr_lab/out/`.

The Dart program maps top-left TSV pixel boxes to bottom-left PDF user space
using PDFium's device-to-page origin and page/raster dimensions. It loads
Helvetica with `FPDFText_LoadStandardFont` and creates one 12 pt object per
word using `FPDFPageObj_CreateTextObj`, the API that takes the loaded font
handle. `FPDFPageObj_NewTextObj` takes a font name. After setting UTF-16 text
and invisible render mode, `FPDFPageObj_GetBounds` supplies natural ink bounds.
The horizontal scale is target width divided by natural width. The vertical
scale is target height divided by natural height, equivalent to scaling the
12 pt base font size. Translation aligns the transformed lower-left edges
with the TSV box, accounting for glyph side bearings and descenders. The
writer applies `FPDFPageObj_Transform`, inserts the objects and regenerates
page content. It streams a full save with flags 0 to a temporary file, then
reopens and verifies it before publishing the output copy.

After reopen, the writer associates each character with its text object.
It compares the union of `FPDFText_GetCharBox` boxes and the union of
`FPDFText_GetRect` selection rectangles with the TSV rectangle. The error is
the absolute difference at each of the four edges. A separate
`FPDFText_FindStart` / `FPDFText_FindNext` check tests each OCR token at
its expected character index. The driver also runs `qpdf --check` and compares
the original and output grayscale raster bytes.

## Linux host results

AMD Ryzen 5 PRO 4650U, x86_64 Linux, Tesseract 5.5.4, Leptonica 1.87.0 and
pinned PDFium 160.0.8179.0. Rasterization is one sample per page. OCR is the
median and range of three fresh CLI processes on each raster.

| Fixture, page | Raster dimensions | Raster ms / peak RSS MiB | OCR ms median (range) | OCR max peak RSS MiB |
| --- | --- | ---: | ---: | ---: |
| scanned-300, 1 | 2550 × 3300 | 302.3 / 40.2 | 660.6 (659.6–677.3) | 76.6 |
| scanned-chapter, 1 | 1425 × 2400 | 137.9 / 26.6 | 1042.6 (1031.3–1159.4) | 67.6 |
| scanned-chapter, 2 | 1425 × 2400 | 103.5 / 26.3 | 1560.7 (1549.3–1575.3) | 71.5 |
| scanned-chapter, 3 | 1425 × 2400 | 95.9 / 26.4 | 1706.3 (1672.2–1720.8) | 72.0 |

| Document | Text-layer write ms | Full save ms | Write + save ms | Dart writer/verification peak RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| scanned-300, one page processed | 63.8 | 6.1 | 69.9 | 325.7 |
| scanned-chapter, three of 36 pages processed | 97.0 | 27.5 | 124.5 | 352.6 |

Write time includes page loading, insertion and content generation. Save time
includes streaming and closing the output file. Reopen and verification occur
after the timed stages. The Dart RSS includes the host JIT and verification.
The memory figures are separate process peaks and cannot be added to estimate
Android app memory.

| Fixture, page | Literal PDFium search hits | Character union mean / max (pt) | Selection union mean / max (pt) |
| --- | ---: | ---: | ---: |
| scanned-300, 1 | 23/23 | 0.00001 / 0.00004 | 0.00001 / 0.00004 |
| scanned-chapter, 1 | 222/224 | 0.00001 / 0.00003 | 0.00001 / 0.00003 |
| scanned-chapter, 2 | 394/396 | 0.00001 / 0.00005 | 0.00001 / 0.00005 |
| scanned-chapter, 3 | 368/371 | 0.00001 / 0.00005 | 0.00001 / 0.00005 |

Both outputs passed `qpdf --check` and all processed pages rasterized
byte-identically before and after insertion. A separate run substituting
`ação` into one TSV word also passed search, extraction and qpdf validation.
PDFium marked all seven misses as hyphenated line endings. Literal queries
including the final hyphen missed even though the word object had aligned
character and selection boxes. The test fails on other search misses.

The maximum fitted edge error is 0.00005 pt, about 0.00021 px at 300 dpi.
The reference is Tesseract's word rectangle, so this measures PDF geometry
round-trip error. Individual glyph positions within a word are distributed
according to Helvetica metrics. OCR accuracy, per-glyph agreement with
independently labeled pixels, phrase search, reading order and general Unicode
coverage need separate checks. In particular, some OCR characters exceed
Helvetica's encoding. The prototype stops on mapping failures, rejects
preexisting text and only handles unrotated scanned pages. Production needs
font coverage and rotated/cropped-page tests.

## To measure on the reference tablet

1. Prepare an Android profile build instrumented with Tesseract4Android
   standard, a dedicated OCR worker, and one asynchronous job at a time.
   Keep PDFium calls on the engine isolate per ADR-0005. Log job/page IDs and
   monotonic timings for model init, 300 dpi raster render, OCR, content write,
   full save, and total page processing. Allow a native stop request while the
   worker is busy. Check cancellation between pages and before publishing a
   save. An Android OCR build is a prerequisite for these steps.
2. Fetch Android PDFium with `tools/fetch_pdfium.sh android`. From the root,
   push both fixtures to the tablet and open them via SAF in the test build.
   Run the profile app and capture its timings and frame data.

   ```sh
   adb -s RXGL20545MJ push test_corpus/scanned-300.pdf /sdcard/Download/
   adb -s RXGL20545MJ push test_corpus/external/scanned-chapter.pdf /sdcard/Download/
   cd app
   flutter run --profile -d RXGL20545MJ
   # In a second terminal
   adb -s RXGL20545MJ logcat -s flutter
   adb -s RXGL20545MJ shell dumpsys meminfo io.github.frerol.doxapdf
   ```

3. From a fresh install of the test build, start OCR and approve the model
   download. Record the bytes written for each model, total model size, and
   download time separately. Verify the hashes above from instrumentation.
   Turn on airplane mode and repeat with both models cached to confirm offline
   recognition.
4. Run one cold process start per fixture with cached models. Then repeat three
   warm runs of scanned-300 page 1 and scanned-chapter pages 1–3 on fresh
   copies of the original inputs. Report per-page medians and maxima, including
   raster and OCR time and the full end-to-end time. Log document save time
   separately for the multi-page batch. Compare typical pages against the
   5 s target. Sample `dumpsys meminfo` before OCR, about once per second during
   the batch, and after cancellation/completion. Record baseline and highest
   sampled TOTAL PSS/RSS, plus the process high-water RSS from
   `/proc/self/status` (`VmHWM`) logged by the app.
5. With the chapter open, establish a control trace for scrolling, pinching
   and drawing with the S Pen at 90 Hz. Start whole-chapter OCR and repeat
   those gestures. Use Flutter frame timing to compare slow frames (>32 ms)
   with the control and repeat the Spike B input-to-pixel measurement against
   the 25 ms budget if the ink harness is available. Cancel once during native
   recognition and once between pages. Log tap-to-worker-stop, check that no
   later page is processed or stale result published, and check that already
   committed annotations and the source survive. Also cancel during a pending
   save, verifying that a partial output cannot replace the source. Retry OCR,
   reopen the output, search for recognized words and select/highlight them.
6. From `app/`, run
   `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64`
   for both the same-revision baseline and OCR-enabled build. For each output
   in `build/app/outputs/flutter-apk/`, record `wc -c` and inspect
   `unzip -lv` for the packaged `lib/<abi>/` entries and storage method.
   Record raw APK byte deltas for armeabi-v7a, arm64-v8a and x86_64, and
   confirm that there are no `.traineddata` assets. Exercise native loading
   on a matching device or emulator for any ABI the reference tablet cannot run.
