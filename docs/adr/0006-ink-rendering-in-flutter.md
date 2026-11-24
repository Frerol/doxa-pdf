# ADR-0006 — Ink rendering in pure Flutter (no native front-buffer path)

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
Pen annotation is a Tier 1 feature, and ink latency was the project's top risk (R1). Flutter has no front-buffered rendering, so the plan
([architecture §6](../plan/03-architecture.md#6-ink-architecture)) kept a fallback: a native Android overlay using `androidx.graphics`
front-buffered rendering and `androidx.input` motion prediction, if pure Flutter missed the 25 ms budget (NFR-PERF-004).
[Spike B](../spikes/B-ink.md) measured this on the reference device (Galaxy Tab S10 FE, S Pen, 90 Hz).

## Decision
Render ink **entirely in Flutter**:
- a raw `Listener` receives every S Pen sample (~480 Hz), with pressure, tilt and buttons;
- the live stroke is drawn as vectors on its own repaint layer;
- committed ink is **rasterized into tiles** and only invalidated where it changes;
- pan/zoom repaints without rebuilding widgets;
- no input prediction, and **no smoothing by default**. Light arc-length smoothing (2–4 px) is optional. The One-Euro filter is not used.

The native front-buffer overlay is **not built**.

## Consequences
- One ink implementation for Android, Linux and Windows, with no platform-specific rendering code.
- Measured event → raster latency is 5–7 ms p50 (≈ 15–20 ms end-to-end with scan-out) on the reference device. Risk R1 drops to Low.
- The tile cache becomes mandatory for ink, not just an optimization. Vector replay of committed ink scaled to 120 ms with 1,500 strokes.
- Desktop pen input is still unverified (risk R2, M5/M6).
- If a later device or a camera test shows unacceptable latency, the overlay can still be added behind `doxa_platform` without changing the ink model.

## Alternatives considered
- **Native front-buffer overlay on Android:** lowest possible latency, but adds Kotlin/GL code, a second rendering path to keep visually
  identical, and a platform-specific feature. Not justified by the measurements.
- **Motion prediction:** prototyped (linear extrapolation). It is unnecessary at the measured latency and risks visible overshoot.
- **One-Euro filtering:** it made strokes look shaky at 480 Hz. The raw digitizer data is already clean (≤ 0.45 px p90 deviation on ruler lines).
