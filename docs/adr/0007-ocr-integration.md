# ADR-0007 — On-device OCR with Tesseract4Android

- **Status:** Proposed
- **Date:** 2026-11-25

## Context
Scanned textbooks are common among students, and without a text layer they cannot be searched, selected or marked up as text.
FR-UTIL-001 asks for OCR that adds an invisible text layer, and NFR-PERF-009 requires that it runs in the background, can be cancelled,
leaves reading and ink smooth, and takes at most 5 s for a typical text page on the reference tablet. The MVP ships it in v0.4
([11 — MVP](../plan/11-mvp.md)) with Portuguese and English models.

Forces:
- Offline and private: recognition must run on the device, with no network access by default ([NFR-SEC-001](../plan/02-requirements.md#25-security--privacy-sec)).
- Licenses must be GPL-3.0-compatible. There is no proprietary SDK such as Google ML Kit.
- PDFium is not thread-safe, and all its calls run in the one engine isolate (ADR-0005). Saves are full saves to a temporary file, then verification and an atomic replace (ADR-0008).
- APK size matters on Android, and the native OCR stack is the largest new binary.

[Spike D](../spikes/D-ocr.md) measured Tesseract4Android 4.9.0 (Tesseract 5.5.1) on the Galaxy Tab S10 FE:
- Speed: the slowest page took 2.6 s from render to text layer, and dense pages have a median of 2.0–2.2 s.
- Cancellation: 32–195 ms from the tap.
- Smoothness: no frame over 32 ms during a whole-document run with pan, zoom and S Pen drawing.
- Memory: about 40 MB of RSS for OCR.
- Alignment: search highlights sat on the scanned words.

## Decision
1. **Engine: Tesseract 5 through [Tesseract4Android](https://github.com/adaptech-cz/Tesseract4Android)** (standard flavour, no OpenMP), pinned to
   4.9.0, on Android. It runs in a **Kotlin worker** on its own background thread, behind a small pigeon API in `doxa_platform`. Dart sends packed
   8-bit grayscale pixels and receives words with boxes and confidences. The worker keeps one initialized `TessBaseAPI` while OCR jobs are
   pending, and releases it when the queue is idle or on `onTrimMemory`.
2. **Models:** `tessdata_fast` 4.1.0 (Apache-2.0), initialized with `por+eng`, OEM 1 (LSTM) and PSM 3. `por` and `eng` (5.81 MiB) are **shipped as
   app assets**, as the MVP plan lists them, so OCR works offline from the first tap, and they are copied to private storage on first use.
   Other languages are **downloaded only on the user's request** from pinned URLs and installed only after a SHA-256 check. This is user-initiated network use, as NFR-SEC-001 allows.
3. **Pipeline**, page by page, in a background queue with lower priority than rendering:
   1. The engine isolate renders the page in grayscale at 300 dpi, capped at 40 MP.
   2. The worker recognizes it.
   3. The engine isolate writes one invisible text object per word into the **editing instance**: an embedded font object
      (`FPDFPageObj_CreateTextObj`), `FPDF_TEXTRENDERMODE_INVISIBLE`, and a transform fitted to the word box from the object's natural bounds.
      The page transforms in `doxa_core` handle rotation and CropBox, and `FPDFPage_GenerateContent` regenerates the content.
   4. The pages of a job are saved together with the ADR-0008 full save → verify → atomic replace, and the render instance reloads them.
4. **Cancellation:** a job carries a generation number, as in ADR-0005. Cancel calls the worker's `stop()`, drops the pages that are not yet
   written, and never publishes a partial job. A save that is already verifying finishes or is discarded as a whole.
5. **Which pages:** OCR runs only on pages without extractable text, unless the user chooses "redo OCR". The user starts it explicitly for the
   page or the document. It is never started automatically in the MVP.
6. **Desktop is decided later** (M5/M6). Likely options are the system `libtesseract` on Linux or a bundled build through FFI, behind the same Dart interface.

## Consequences
- The APK grows by about 7.2 MiB per ABI (stored native libraries) plus 5.8 MiB of models. Split APKs per ABI keep a single download near that.
- `doxa_platform` gains an OCR API and a Kotlin worker. The engine gains a text-layer writer with unit tests for fit, rotation, CropBox and search alignment.
- **Font coverage:** the invisible text needs a font that can encode every recognized character. The spike's Helvetica cannot, so a small embedded
  font with wide Unicode coverage is needed. Choosing it is a task for M4 and must respect the license rules.
- **Supply chain:** the AAR comes from JitPack in the spike. Before a release it must be built from the tagged source in CI or vendored as a
  verified artefact, and F-Droid will require a source build (M7). The Gradle license check must list its native components.
- **Notices:** the licenses screen must include Tesseract and the wrapper (Apache-2.0), Leptonica (BSD-2-Clause), libjpeg (IJG), libpng
  (libpng-2.0), zlib, and LLVM libc++ (Apache-2.0 with LLVM exceptions), plus the tessdata license.
- **Pitfall from the spike:** the production reader must never let stylus pointers reach pan/zoom recognizers, or ink nudges the page (AGENTS.md §7).
- R13 (OCR speed, memory and alignment) is retired for the tested pages. Rotated pages, recognition quality and battery use stay to be measured in M4.

## Alternatives considered
- **Tesseract + Leptonica built with the NDK, called from Dart FFI:** reusable on desktop and gives full control of the binary, but Doxa would own
  the native build for three ABIs, the bindings and every upgrade, and a blocking FFI call needs its own isolate and a cancellation monitor. It
  stays the fallback if Tesseract4Android stops being maintained.
- **Tesseract CLI as a subprocess:** easy to kill, but Android 10+ restricts executing binaries, and the packaging was never proven.
- **Google ML Kit or other proprietary OCR SDKs:** proprietary and incompatible with the project's rules.
- **Downloading `por` and `eng` on first use instead of shipping them:** saves 5.8 MiB, but the first OCR would need a network and a prompt. Kept for the other languages.
- **`tessdata_best` models:** more accurate, but several times larger and slower. They can be offered later as an optional download.
