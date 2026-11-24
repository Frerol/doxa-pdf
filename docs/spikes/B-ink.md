# Spike B — S Pen ink latency, pressure and palm rejection

- **Issue:** #6 · **Date:** 2026-11-24 · **Result: GO, pure Flutter** (see [ADR-0006](../adr/0006-ink-rendering-in-flutter.md))
- **Device:** Samsung Galaxy Tab S10 FE (SM-X520), Android 16, 90 Hz display, S Pen (Wacom EMR `sec_e-pen`)
- **Build:** Flutter 3.50.1, **profile mode**, Impeller on Vulkan
- **Prototype:** `spikes/ink_lab/` on the [`spike/ink`](https://github.com/Frerol/doxa-pdf/tree/spike/ink/spikes/ink_lab) branch (not merged)

## Method
Three test rounds with the maintainer writing on the device, ~80 strokes in total. The prototype logged one line per stroke through
`adb logcat`. Raw digitizer events were captured in parallel with `adb shell getevent` for comparison.

Latency is measured as **event timestamp → raster finished** for the frame that shows the newest input event. Pointer timestamps and
`FrameTiming` both use the monotonic clock. This metric **excludes display scan-out**, which adds ≤ 1 refresh (11.1 ms at 90 Hz) plus compositor time.

## Findings

### 1. Input: Flutter receives every S Pen sample
| Metric | Value |
|---|---|
| Digitizer report rate (`getevent`) | **483 Hz** (2.07 ms) |
| Events reaching Dart | **~480 Hz**, i.e. no batching loss |
| Event → Dart handler | **1.3 ms p50**, 2–3 ms p95 |
| Pressure | `pressure` normalized 0..1 (`pressureMin/Max` 0..1; hardware 4096 levels). Raw jitter 0.1% |
| Tilt / orientation | Reported (`tilt` in radians, 0.2–1.1 observed) |
| Side button | `buttons` = `kPrimaryStylusButton` (2) while pressed. Erasing with it works |
| Eraser end / `invertedStylus` | Not available on this S Pen model |
| Hover | Hover events arrive (used for palm rejection). `distance` is **not** exposed (`distanceMax` 0) |

### 2. Latency is well inside the budget
| Scenario | Event → raster p50 | p95 |
|---|---|---|
| Empty canvas | 5.3–6.8 ms | 7.4–9.0 ms |
| 1,500+ committed strokes, vectors replayed every frame (v1) | **114–125 ms** | 119–131 ms |
| 1,500+ committed strokes, committed ink baked to an image (v2/v3) | **5.4–5.7 ms** | 7.0–7.7 ms |

Estimated end-to-end with scan-out: **≈ 15–20 ms** < 25 ms budget (NFR-PERF-004). The maintainer did not perceive lag ("I did not find the latency bad").
A front-buffered native path is therefore **not needed**. A high-speed camera check remains a release-checklist item ([QA §4](../plan/06-quality-assurance.md#4-performance-budgets)).

### 3. Committed ink must be rasterized, not replayed
Replaying every committed stroke as vectors each frame made latency grow linearly with the amount of ink. It reached ~1 ms per long stroke,
and 120 ms with 1,500 strokes. Baking committed ink into a device-resolution image fixed it completely. In the product this becomes the
**tile cache** ([architecture §4](../plan/03-architecture.md#4-engine-worker-and-rendering-pipeline)): committed annotations are rasterized per tile, and only the live stroke is drawn as vectors.

Erasing re-baked everything in the prototype. With 1,500 strokes, the input rate fell to ~250–330 Hz and erasing felt sluggish. **Erase and edit
must invalidate only the affected tiles.**

### 4. Pan/zoom
The first version rebuilt the whole widget tree on every gesture update and re-baked on release, and zoom was "not fluid at all". With the
transform in a `ValueNotifier` (repaint only, no rebuild), and the previous bake transformed until it is re-baked, zoom became "much better":
build ~0.4 ms, raster ~2.5 ms p50, ≤ 1 janky frame per gesture. Strokes were never blurry, because re-baking after the gesture restores sharpness.

### 5. Palm rejection
The rule was: ignore touches while the pen is down, or for 300 ms after the last pen event (including hover). Over ~30 palm contacts while writing,
**all were rejected**. None scrolled, zoomed or drew. Fingers still pan and zoom when the pen is away.

### 6. Stroke quality: raw input is clean, so don't over-filter
- With a **ruler**, straight lines deviate from a fitted line by **0.14–0.20 px p50, ≤ 0.45 px p90** over 430–480 px. The digitizer does not wobble.
- Sample-to-sample jitter at the Dart level is 0.03–0.14 px p50, which is the digitizer's resolution (0.056 logical px per raw unit).
- The "shaky / squiggly" look in round 1 came from the **rendering and filtering** (tiny per-segment lines plus a One-Euro filter tuned for
  lower rates), not from the pen.
- Maintainer's verdict comparing modes on the same word: **off ≈ arc 2 px ≈ arc 4 px** (best, with "off" preferred), **One-Euro looked shaky**, and
  **arc 8 px over-smoothed**.
- Filled variable-width outline vs. per-segment lines: no visible difference for the maintainer. The outline is still preferred, because it maps directly to the
  annotation's appearance stream (filled path) and avoids cap overdraw.

## Decisions for the product (`doxa_ink`)
1. **Pure Flutter ink pipeline** with a raw `Listener`. There is no native front-buffer overlay on Android ([ADR-0006](../adr/0006-ink-rendering-in-flutter.md)).
2. **Default smoothing: off.** Offer an optional *light* arc-length smoothing (2–4 px) setting. **Do not use the One-Euro filter.**
3. Keep all samples (480 Hz) in the stroke model. Resample by distance (~0.5 px) only for rendering and storage.
4. **Live stroke as vectors on its own layer; committed ink rasterized into tiles.** Erasing and editing invalidate only the touched tiles.
5. Transform changes (pan/zoom) repaint without rebuilding widgets. Reuse cached tiles transformed until re-rendered.
6. Palm rejection: pen down or pen seen ≤ 300 ms ago → reject touches. Side button (`kPrimaryStylusButton`) → eraser while held.
7. Prediction: not needed at the measured latency. Revisit only if a camera test disagrees.

## Follow-ups
- High-speed camera end-to-end measurement before v0.2 (release checklist).
- Repeat on a low-end Android tablet without a stylus (finger drawing), and on desktop pens in M5/M6 (risk R2).
- Pressure curve setting UI and tuning of width range (FR-INK-002) with real handwriting samples.
