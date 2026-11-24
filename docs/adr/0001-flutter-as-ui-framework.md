# ADR-0001 — Flutter as the cross-platform UI framework

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
Doxa PDF targets Android, Windows and Linux with one small team. The product is UI-heavy (reader, tool palettes,
custom-drawn annotations and ink) and needs consistent behaviour across platforms, high frame rates and access to native code (PDFium).

## Decision
Use **Flutter** (stable channel, pinned with FVM) for the whole UI, with Dart FFI for PDFium and platform plugins for native gaps.

## Consequences
- One UI codebase; custom rendering (annotation and ink layers) is natural with `CustomPainter`/layers.
- Mature Android support; Windows and Linux embedders are good but weaker on **stylus input**. This is validated in M0 (risk R2).
- No front-buffered rendering in Flutter, so the lowest-latency ink on Android may need a native overlay (risk R1).
- iOS/macOS become cheap future targets.

## Alternatives considered
- **Kotlin Multiplatform + Compose**: best on Android, but the desktop version runs on the JVM (heavier packaging) and has a smaller desktop ecosystem.
- **Rust core + Tauri 2**: a light desktop app, but Android support is younger and a web UI makes low-latency ink harder.
- **Qt/QML**: native performance, but slower development and LGPL/commercial licensing complexity.
