# Spike D — On-device OCR

- **Issue:** #8 · **Date:** 2026-11-25 · **Result: GO** with Tesseract4Android through a Kotlin bridge (see [ADR-0007](../adr/0007-ocr-integration.md))
- **Requirements:** FR-UTIL-001, NFR-PERF-009 (≤ 5 s per typical text page on the reference tablet, in the background, cancellable)
- **Engine:** PDFium 160.0.8179.0 through `pdfium_ffi`; Tesseract 5.5.1 (Android) / 5.5.4 (Linux host); `tessdata_fast` 4.1.0 `por+eng`
- **Prototypes:** `spikes/ocr_lab/` (Linux host, text-layer writer and benchmark) and `spikes/ocr_android/` (tablet harness) on the
  [`spike/ocr`](https://github.com/Frerol/doxa-pdf/tree/spike/ocr/spikes) branch (not merged)
- **Device:** Galaxy Tab S10 FE (SM-X520), Android 16, 90 Hz, profile build, arm64-v8a

## Summary

| Question | Answer |
|---|---|
| Fast enough? | **Yes.** The slowest page took 2.6 s from render to text layer. Dense chapter pages have a median of 2.0–2.2 s, and a sparse 300 dpi page takes 0.35 s. The target is 5 s. |
| Does the text layer line up? | **Yes.** Fitted word boxes are within 0.00005 pt of Tesseract's boxes on the host. PDFium search highlights land on the scanned words on the tablet at every zoom level checked. |
| Does it disturb reading and ink? | **No.** While a whole-document OCR ran with touch pan/zoom and S Pen drawing, 7 of 1,206 frames exceeded 16.7 ms and none exceeded 32 ms. The control run had 2 of 1,864 over 16.7 ms. |
| Cancellable? | **Yes**, 32–195 ms from tap to stop, and a cancelled job never publishes. |
| Cost | About 7.2 MiB of native libraries per ABI (stored) in the APK, plus 5.81 MiB for the `por` and `eng` models. OCR itself adds about 40 MB of RSS. |

## Android integration options

All three paths can use the same Apache-2.0 [tessdata_fast 4.1.0 models](https://github.com/tesseract-ocr/tessdata_fast/tree/4.1.0):
`por.traineddata` (1,982,756 B, SHA-256 `c4932b93…7deb`) and `eng.traineddata` (4,113,088 B, SHA-256 `7d4322bd…70b2`), 5.81 MiB in total.
The tested page segmentation mode (PSM 3) needs no OSD model.

| Route | Maintenance and ABI support | APK delta per ABI, excluding models |
|---|---|---|
| **Tesseract4Android** (standard flavour) via a small Kotlin platform channel | Upstream release 4.9.0 bundles Tesseract 5.5.1 with Leptonica, libjpeg 9f and libpng 1.6.48 for arm64-v8a, armeabi-v7a, x86 and x86_64. The Java API exposes word results through the iterator and cooperative cancellation through `stop()`. [Release](https://github.com/adaptech-cz/Tesseract4Android/releases/tag/4.9.0) | **Measured:** 7.17 MiB (arm64-v8a), 5.26 MiB (armeabi-v7a), 7.58 MiB (x86_64), stored |
| Tesseract + Leptonica built with the NDK, C API from Dart FFI | Active upstreams (Tesseract 5.5.4, Leptonica 1.87.0). Doxa would own the native builds, bindings and upgrades. A synchronous FFI call needs its own worker isolate and a cancellation monitor. Reusable on desktop. [C API](https://github.com/tesseract-ocr/tesseract/blob/5.5.4/include/tesseract/capi.h) | Estimated 7–10 MiB stored (not built) |
| NDK-built Tesseract CLI subprocess | Same upstreams. Executable packaging and launch from the APK must be proven under Android 10+ execution restrictions. [Restrictions](https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission) | Estimated 7–11 MiB stored (not built) |

Verified in the 4.9.0 AAR resolved by Gradle: `libtesseract.so` reports 5.5.1, `libpngx.so` 1.6.48, and `libjpeg.so` 9f (14-Jan-2024).
`libtesseract.so` links only Android system libraries plus the bundled Leptonica, libjpeg and libpng: there is no OpenMP, libarchive or curl,
and the C++ runtime is linked statically. Leptonica's exact version is not embedded in the binary; upstream's tagged README lists 1.85.0.

Licenses: the wrapper and Tesseract are Apache-2.0, Leptonica BSD-2-Clause, libjpeg IJG, libpng libpng-2.0, the platform zlib Zlib, and the
static LLVM libc++ Apache-2.0 with LLVM exceptions. All are GPL-3.0-compatible and need notices in the app's licenses screen.
[Tagged dependency list](https://github.com/adaptech-cz/Tesseract4Android/blob/4.9.0/README.md) ·
[IJG](https://www.ijg.org/files/README) · [libpng](https://github.com/pnggroup/libpng/blob/v1.6.48/LICENSE) ·
[LLVM runtime terms](https://github.com/llvm/llvm-project/blob/main/libcxx/LICENSE.TXT)

## Method

**Linux host (`spikes/ocr_lab/`).** `benchmark.py` rasterizes each page with Poppler at 300 dpi grayscale, then runs the Tesseract CLI three
times (`OMP_THREAD_LIMIT=1`, `por+eng`, OEM 1, PSM 3, TSV output). The Dart writer (`bin/text_layer.dart`) maps the top-left TSV boxes to
bottom-left PDF user space and loads Helvetica with `FPDFText_LoadStandardFont`. It creates one 12 pt object per word with
`FPDFPageObj_CreateTextObj`, sets UTF-16 text and `FPDF_TEXTRENDERMODE_INVISIBLE`, and fits it to the word box with `FPDFPageObj_Transform`:
the scale comes from the object's natural bounds (`FPDFPageObj_GetBounds`) and the translation compensates for side bearings and
descenders. It then inserts the objects, regenerates the content and saves (full save, flags 0) to a temp file, and verifies the file
before publishing. Verification reopens the file and compares the per-word unions of `FPDFText_GetCharBox` and `FPDFText_GetRect` with
the TSV box, runs `FPDFText_FindStart`/`FindNext` for every token, runs `qpdf --check`, and compares rasters before and after.

Reproduce (from the repository root, with FVM's Dart on PATH):

```sh
tools/fetch_pdfium.sh linux && tools/fetch_corpus.sh
cd spikes/ocr_lab && dart pub get && mkdir -p out/tessdata
for lang in por eng; do
  curl --fail --location "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/$lang.traineddata" \
    --output "out/tessdata/$lang.traineddata" || exit
done
python3 benchmark.py ../../test_corpus/scanned-300.pdf 1
python3 benchmark.py ../../test_corpus/external/scanned-chapter.pdf 1 2 3
```

**Tablet (`spikes/ocr_android/`).** A Flutter harness with a Kotlin worker on `cz.adaptech.tesseract4android:tesseract4android:4.9.0`
(from JitPack). The worker receives packed 8-bit grayscale pixels rendered by PDFium, calls the interruptible `getHOCRText`, and reads
words, confidences and rectangles from the result iterator. It initializes `por+eng` with OEM 1 and PSM 3. On the first OCR request,
the app downloads the pinned models and installs them only after their SHA-256 matches. PDFium rendering and the text-layer writer run as
on the host. The app logs per-stage timings, `VmHWM`/`VmRSS`, frame-time traces and cancellation timings, and `dumpsys meminfo` was
sampled every 3 s. Each OCR run starts from the original PDF and replaces the app's private verified copy only on success.

## Results on the reference tablet

### Speed (warm, three runs each, median)

| Fixture, page | Raster | Words | Render ms | OCR ms | Write ms | Page ms (render → text layer) |
|---|---|---:|---:|---:|---:|---:|
| scanned-300, 1 | 2550 × 3300 | 23 | 111 | 213 | 3 | **352** |
| scanned-chapter, 1 | 1425 × 2400 | 224 | 61 | 1,146 | 27 | **1,259** |
| scanned-chapter, 2 | 1425 × 2400 | 396 | 48 | 1,898 | 4 | **1,997** |
| scanned-chapter, 3 | 1425 × 2400 | 371 | 56 | 1,948 | 5 | **2,045** |

- Run-to-run spread stayed below 3%. Whole chapter, 27 pages before cancellation: page median **2,194 ms**, maximum **2,599 ms**.
- Saving and verifying (full save of the 31 MB chapter, then reopen): 47–54 ms save + 12–13 ms verification for a 3-page batch.
- Model cost: the first-ever run downloaded the models in 0.67 s (`por`) and 0.43 s (`eng`) over Wi-Fi. Both hashes matched. `init` took 182–190 ms
  on a cold process and 0 ms afterwards, because the worker keeps the API loaded. Airplane-mode runs worked from the cached models.
- The first run in a fresh process (cold, models cached) took 360 ms for the scanned-300 page, the same as warm.
- Compared with the single-threaded host CLI (Ryzen 5 PRO 4650U): dense chapter pages take 10–20% longer on the tablet (1.15–1.95 s against
  1.04–1.71 s). The sparse page looks faster on the tablet (213 ms against 661 ms) only because the host numbers include process start and model load.

### Alignment
The maintainer searched several words visible on the chapter scans. Every highlight (PDFium selection rectangles of the hit) sat on the printed
word, at several zoom levels. On the host, all fitted word boxes were within 0.00005 pt (about 0.0002 px at 300 dpi) of Tesseract's boxes.
Literal search found 1,007 of 1,014 tokens. The 7 misses were words hyphenated at line ends, which PDFium joins. Outputs passed `qpdf --check`,
and pages rasterized byte-identically before and after insertion, so the invisible text changes nothing visible.

### Memory
| Measure | Value |
|---|---|
| OCR-attributable RSS (VmRSS during recognition minus before) | ≈ 40 MB |
| Process `VmHWM` over all runs | 379 MB |
| `dumpsys meminfo` total PSS, chapter open, during OCR | 460–498 MB, of which **254 MB is graphics** (EGL/GL mtrack) and 116 MB native heap |

The graphics share comes from the harness viewer, which keeps full-page `ui.Image`s at screen resolution. The production reader uses previews and
512 px tiles with an LRU (ADR-0005), so the OCR budget to plan for is about 40 MB on top of the reader's own footprint (R14).

### Smoothness during OCR
| Trace | Frames | > 16.7 ms | > 32 ms |
|---|---:|---:|---:|
| Control: touch pan/zoom + S Pen drawing, no OCR | 1,864 | 2 | 0 |
| Whole-document OCR (60 s) with the same gestures | 1,206 | 7 | 0 |

The maintainer felt no stutter during OCR. Two limitations: the harness counts frames against 16.7 ms (60 Hz), while the panel runs at 90 Hz
(11.1 ms budget), and the Spike B input-to-pixel latency rig was not repeated. The production reader should repeat this trace against the 90 Hz budget.

**Harness artefact, not an OCR finding:** S Pen strokes scrolled the page a little. The harness wraps its ink `Listener` in an
`InteractiveViewer` and disables panning only after the pen's pointer-down, by which time the viewer's recognizer has already joined the
gesture arena. Spike B's own gesture handling never let stylus pointers reach pan/zoom, and the production reader must do the same (AGENTS.md §7).

### Cancellation
| Cancelled while… | Native `stop()` | Tap → cancelled | Outcome |
|---|---:|---:|---|
| Recognizing the first page | 25 ms | 32 ms | No page done, nothing published |
| Recognizing, just after a page finished | 44 ms | 55 ms | 1 page done, nothing published |
| Recognizing page 28 of a whole-document run (60 s in) | 182 ms | 195 ms | 27 pages done, nothing published |
| Saving and verifying | — | — | Not caught: the save of a batch lasts about 50 ms |

In every case the previous verified copy, the source PDF and the in-memory test strokes survived. Cancel during save will be covered by a
unit test in the production engine, which only replaces the file after verification (ADR-0008).

### APK size (Linux build of the harness, split release APKs, native libraries stored)
| ABI | Release APK | Tesseract4Android native libraries |
|---|---:|---:|
| arm64-v8a | 30,897,968 B | 7.17 MiB |
| armeabi-v7a | 24,200,778 B | 5.26 MiB |
| x86_64 | 32,917,115 B | 7.58 MiB |

No `.traineddata` file is in any APK. The Java wrapper adds little (`classes.jar` is 49,997 B).

## Limits and follow-ups
- **Font coverage:** Helvetica (standard encoding) cannot represent every OCR character. Production needs an embedded font with wide Unicode coverage
  for the invisible text, or a fallback per glyph. Test with Portuguese diacritics (`ação` passed on the host) and symbols.
- **Page geometry:** the prototype handles unrotated pages only. It must be extended to `/Rotate` and CropBox pages, reusing the `doxa_core` page transforms (T-04).
- **Existing text:** the prototype refuses pages that already have text. Production must detect scanned pages (no text, or text with an
  invisible render mode from another OCR tool) and offer to redo the OCR.
- **Recognition quality** (accuracy, reading order, phrase search across lines) was not measured. Hyphenated line ends are a known PDFium search behaviour.
- **Supply chain:** the AAR comes from JitPack. Before release, build it from the tagged source in CI, or vendor a verified artefact. F-Droid
  will need a source build anyway (M7).
- **Threads:** the standard flavour has no OpenMP, so recognition uses one core. Recognizing two pages on separate workers could roughly halve
  batch time. Measure the effect on frame times, memory and battery in M4 before trying it.

## Go / no-go
**GO.** Tesseract4Android meets NFR-PERF-009 with more than 2× headroom on the densest pages tested, stays cancellable within 0.2 s, and leaves
reading and ink smooth. The decision and its integration rules are in [ADR-0007](../adr/0007-ocr-integration.md).
