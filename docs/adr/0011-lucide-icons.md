# ADR-0011 — Lucide as the app icon set

- **Status:** Accepted (maintainer decision, #156)
- **Date:** 2026-11-27

## Context

The open-book icon was unclear as a dictionary action and also represented the two-page reader layout. Mixing icon sets would make the interface look inconsistent.

## Decision

Use Lucide for all app-defined icons at the default 2 px stroke weight. Use distinct icons for the dictionary, two-page layout and cover layout.

The app depends on `lucide_icons_flutter` 4.0.5 (MIT), which bundles [Lucide 1.81.0](https://github.com/lucide-icons/lucide/tree/1.81.0) glyphs (ISC, with an MIT notice for icons derived from Feather). Bundle the upstream [Lucide notice](../../app/assets/licenses/lucide.txt) and register it with the app's licences page.

## Consequences

Lucide's outlined glyphs stay the same when the favourite and side-panel toggles are selected. A tonal container appears around the selected icon, and the button exposes its selected state through accessibility semantics.

The app theme supplies Lucide glyphs for the framework's back, close and drawer buttons and the selected mark on segmented buttons. Internal framework glyphs without a theme override retain their defaults.

## Alternatives considered

- Keep Material icons across the app. The approved Lucide set provides distinct symbols for the dictionary and page layouts.
- Use Lucide only for the dictionary. This would mix different stroke styles in the same toolbar.
