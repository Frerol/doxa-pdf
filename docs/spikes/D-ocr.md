# Spike D — On-device OCR

**Issue #8 · Draft · Linux host results.** PDFium preserved the page images and
made the OCR text selectable on both fixtures. The Android measurement harness is in `spikes/ocr_android/`. The APK build
and the Galaxy Tab S10 FE performance decision are pending. This spike covers
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

The harness uses Tesseract4Android standard
`cz.adaptech.tesseract4android:tesseract4android:4.9.0` from the
[JitPack Maven repository](https://jitpack.io).
The Kotlin worker submits packed 8-bit grayscale pixels, calls the
interruptible `getHOCRText` entry point and reads words, confidence and
rectangles from the result iterator. The app loads `por+eng` with OEM 1
and PSM 3, downloads the pinned models on the first OCR request and
verifies SHA-256 before installing either file. The Linux engine test
covers 300 dpi rasterization, full save, reopen and search rectangle
alignment for a synthetic Portuguese OCR result. Android compilation
stopped at the Gradle wrapper lock on the sandbox's read-only filesystem,
so APK sizes and Android runtime behavior are pending.

1. From the repository root, prepare the fixtures and install the profile build.

   ```sh
   export JAVA_HOME="$HOME/.local/share/jdk/17"
   export ANDROID_HOME="$HOME/Android/Sdk"
   export PATH="$PWD/.fvm/flutter_sdk/bin:$ANDROID_HOME/platform-tools:$PATH"
   tools/fetch_pdfium.sh android
   tools/fetch_corpus.sh
   adb -s RXGL20545MJ push test_corpus/scanned-300.pdf /sdcard/Download/
   adb -s RXGL20545MJ push test_corpus/external/scanned-chapter.pdf /sdcard/Download/
   cd spikes/ocr_android
   flutter build apk --profile
   adb -s RXGL20545MJ install -r build/app/outputs/flutter-apk/app-profile.apk
   adb -s RXGL20545MJ shell am start -n io.github.frerol.doxapdf.ocrlab/.MainActivity
   ```

   In a second terminal, capture the app and native logs.

   ```sh
   "$HOME/Android/Sdk/platform-tools/adb" -s RXGL20545MJ logcat -v threadtime -s flutter:I OCRLAB:I |
     tee ocrlab-tablet.log
   ```

2. With fresh app data and network access, tap **Open PDF**, choose
   `scanned-300.pdf` from Downloads, then tap **OCR this page**. That
   button initiates the model download. Copy both native `OCRLAB model=`
   lines with bytes, hashes and download time. Turn on airplane mode
   and repeat to check cached recognition.
3. With models cached, force-stop and relaunch the app for one cold
   run per fixture. Tap **OCR this page** for `scanned-300.pdf` and
   **OCR first 3 pages** for `scanned-chapter.pdf`. Repeat each three
   times in the same process for warm runs. Each run starts from the
   SAF input snapshot and replaces its private verified copy on success.
   Use **Search** to look up words visible on the scan and **Next hit**
   to navigate matches. Check the highlighted PDFium selection rectangles
   against the printed words at different zoom levels.
4. Copy the `OCRLAB` lines containing `model_init_ms`,
   `stage=page_done`, `stage=save_start`, `stage=published`, and
   `memory=before`, `memory=during` and `memory=after`. Calculate
   per-page median and maximum from `page_ms` and compare with the 5 s
   target. `page_ms` covers render through text-layer write, while
   `total_ms` measures the entire batch through publication. The
   `full_save_ms` and `verified_ms` values describe one shared
   document save and reopen. The `VmHWM` and `VmRSS` samples are
   in kB. For PSS, record the `TOTAL` line before, during and after
   a batch with:

   ```sh
   adb -s RXGL20545MJ shell dumpsys meminfo io.github.frerol.doxapdf.ocrlab
   ```

5. On the chapter, tap **Start control trace**, pan and pinch with touch,
   and draw with the S Pen. Tap **End control trace** and repeat those
   gestures during **OCR whole document**. Copy the `trace=` lines with
   total frames and counts over 16.7 ms and 32 ms. In separate runs, tap
   **Cancel** while the status says **Recognizing page**, near a
   `stage=page_done` boundary and while **Saving and verifying PDF**
   is visible. Copy `cancel_requested`, `native_stop_ms` when present,
   and `outcome=cancelled` with `cancel_ms`. Check for no
   `stage=published` for the cancelled job and confirm the previous
   verified copy, source PDF and in-memory test strokes survive.
   Repeat the Spike B input-to-pixel test against 25 ms if its equipment
   is available.
6. For APK-size measurements, build and inspect the split release
   outputs from `spikes/ocr_android/`.

   ```sh
   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
   for apk in build/app/outputs/flutter-apk/*-release.apk; do
     wc -c "$apk"
     unzip -lv "$apk" | awk '/lib\/|\.traineddata/'
   done
   ```

   Record the byte counts and native entries for armeabi-v7a, arm64-v8a
   and x86_64, confirm no `.traineddata` assets are present and
   exercise native loading on a matching device or emulator. To
   measure the Tesseract APK delta, compare with a same-revision build
   of the harness with the OCR bridge and Maven dependency removed.

## Build outputs on Linux (not tablet measurements)

`spikes/ocr_android` builds with the app's Gradle 9.9.2, AGP 9.5.2 and Kotlin 2.4.21; the Kotlin bridge compiles.
Split release APKs (all native libraries stored uncompressed), with no `.traineddata` assets:

| ABI | Release APK | Tesseract4Android native libs (`libtesseract`, `libleptonica`, `libjpeg`, `libpngx`) |
| --- | ---: | ---: |
| arm64-v8a | 30,897,968 B | 7.17 MiB |
| armeabi-v7a | 24,200,778 B | 5.26 MiB |
| x86_64 | 32,917,115 B | 7.58 MiB |

The native libraries are the bulk of the OCR APK delta and fall within the "stored" estimate above; the Java wrapper adds little.
The profile APK (all ABIs) is 108.3 MB.
