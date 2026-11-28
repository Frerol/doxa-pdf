# ADR-0012 — Filled Lucide star for favourites

- **Status:** Accepted
- **Date:** 2026-11-28

## Context

Issue #161 makes the favourite toggle available in the home dashboard and reader (FR-FILE-005).
[ADR-0011](0011-lucide-icons.md) uses a tonal container to indicate selection because the Lucide icon set supplies outlined glyphs.
The maintainer chose a filled star for favourites so that the shape indicates the state in both buttons and menus.

## Decision

Use the standard Lucide star for documents outside Favourites. For documents in Favourites, fill and stroke the same
[Lucide 1.81.0 star path](https://github.com/lucide-icons/lucide/blob/1.81.0/icons/star.svg) with a Flutter custom painter.
The path is ISC-licensed and covered by the [bundled Lucide notice](../../app/assets/licenses/lucide.txt).

Use both shapes on the dashboard and in the full lists and reader. Keep action labels and expose the selected state to accessibility services.

## Consequences

This amends the selected-state consequence of [ADR-0011](0011-lucide-icons.md) for favourites. The reader's side-panel button retains the tonal container.
The icon needs no new dependency. The filled path is maintained alongside the outlined glyph and should be reviewed when Lucide is updated.

## Alternatives considered

- Keep the tonal container. The two states would share the same silhouette.
- Use a filled glyph from another set. Its shape could differ from the Lucide outline.
