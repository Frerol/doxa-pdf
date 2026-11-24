# ADR-0004 — Monorepo with Dart pub workspaces

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
The code splits naturally into an app plus several packages (domain, ink, engine, FFI bindings, platform plugin) that change together.

## Decision
Use a single repository with **Dart pub workspaces** (`app/` + `packages/*`), a single lockfile and shared analysis options.
Use melos only if workspace scripts outgrow simple `tools/` scripts.

## Consequences
- Atomic cross-package changes and a single CI pipeline.
- Package boundaries enforce the dependency rule in docs/plan/03 §2, and `doxa_core` stays pure Dart.

## Alternatives considered
- **Multiple repositories**: too much overhead for one team.
- **A single package with folders**: no enforced boundaries, and the core is harder to test without Flutter.
