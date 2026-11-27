# Clean-room standard

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are used as in RFC 2119 and RFC 8174. If you depart from a SHOULD, say so in the PR and why.

This standard says where knowledge, code, assets and test files may come from. It applies to everyone, people and agents. [AGENTS.md](../../AGENTS.md) has the short form.
It builds on [licensing hygiene](../plan/10-governance.md#4-licensing-hygiene) and on the UX rule to resemble the leading commercial readers in layout and flows while keeping an original identity ([05 — UX Design §8](../plan/05-ux-design.md)).

## 1. Where knowledge comes from

You MAY learn from:

- public specifications: ISO 32000 (PDF), the StarDict and dictzip formats, Android and Flutter documentation;
- public documentation of other products: help pages, published screenshots, tutorial videos;
- papers and textbooks;
- behaviour specifications written as section 3 describes;
- source code under a licence compatible with GPL-3.0-or-later, following section 2.

You SHOULD cite the source in the code or ADR: the specification and its edition (for example "ISO 32000-2:2020 §12.5.6.10"), or the project and file a technique came from.

You MUST NOT use remembered knowledge of a proprietary product's internals (class names, private file formats, database layouts, server APIs). A fact that no public source, behaviour specification or test file shows MUST NOT go in.

## 2. Code from other projects

Doxa is GPL-3.0-or-later, so it can reuse code under compatible licences ([ADR-0003](../adr/0003-gpl-3-license.md)).

- You MAY read and reuse code under MIT, BSD, Apache-2.0, MPL-2.0, LGPL or GPL-3.0(-or-later). Reused code MUST keep its copyright and licence notice, and the PR MUST name the source (project, file, version or commit) and add it to the third-party notices when it ships.
- You MUST NOT copy code from proprietary sources, from leaked or decompiled code, or from licences that are not compatible with GPL-3.0-or-later (for example GPL-2.0-only, non-commercial or unlicensed code).
- You MUST NOT copy, link or bundle AGPL code. This includes MuPDF ([decided stack](../adr/0002-pdfium-as-pdf-engine.md)). AGPL and other copyleft tools MAY run as **separate processes** in tests and CI, for example to render our saved files for interop checks. They MUST NOT ship with the app.
- A dependency follows the licence check in `tools/check_dependency_licenses.py` and needs the maintainer's approval first.

## 3. Learning from a proprietary app

Doxa follows the layout and flows of a commercial PDF reader, but nothing of its code, artwork or text. To keep what we observe apart from what we write, the work has two roles. One agent session MUST NOT take both.

**Observer.** A person or agent that uses the proprietary app.

- MUST use it only with documents we generated or that the person owns, never the user's own files, account or cloud.
- SHOULD write a **behaviour specification**: what a user sees and does, screen by screen (controls, their order, gestures, results), in our own words and without naming the product.
- MUST NOT instrument the app: no decompiling, no reading its APK or install files, no memory, traffic or log inspection, no copying its fonts, icons, presets or sample files.
- SHOULD capture only the app's own screen, never notifications or other apps.

**Implementer.** A person or agent that writes Doxa code.

- MUST NOT operate the proprietary app or read its install.
- Works from the behaviour specification, public documentation and specifications.

**Captures.** Screenshots, recordings and observation notes MUST NOT be committed, attached to issues or PRs, or traced. Keep them outside the repository. Only the generic requirements derived from them go into `docs/plan/` (as in [05 — UX Design §8](../plan/05-ux-design.md)).

**Interop checks are allowed.** Opening files that Doxa saved in other readers, to check that our annotations display correctly, is compatibility testing and not learning the app's internals ([06 — Quality Assurance §3](../plan/06-quality-assurance.md#3-pdf-test-corpus--interoperability)).

## 4. Assets and UI

- An asset is any non-code material the project includes, ships or shows in its docs: icons, logos, illustrations, fonts, colours, sounds, screenshots, sample documents, and bytes embedded in code.
- Every asset MUST be either our own work under the project licence, or under a GPL-3-compatible licence and taken from its original source (not a mirror), with its source, version and licence recorded in the same change.
- You MUST NOT use assets from a proprietary product, its installer, website or documents. This includes traced, redrawn, recoloured or lookalike copies, and placeholders.
- You MAY follow another product's layout, arrangement and conventions. Every icon, colour, font and text MUST be chosen or written by us. Icons come from Lucide ([ADR-0011](../adr/0011-lucide-icons.md)), and colours come from the Doxa palette. You MUST NOT sample colours or trace shapes from another app's screens.
- The product that inspired Doxa (observed under section 3) MUST NOT be named in the repository, including file names, commits, issues and PRs. Write "a commercial PDF reader".
  Other products MAY be named where needed for interoperability targets, engines and libraries, specifications, or sources required by sections 2 and 5.
  `tools/check_repo_rules.py` checks this rule against a list kept outside the repository (the CI secret `DOXA_FORBIDDEN_NAMES` or a local git-ignored `.forbidden-names`).
- Translations SHOULD be written from the meaning of the English text, not from another app's localisation.

## 5. Fixtures and test corpus

Every test file MUST be one of:

1. **Generated** by a committed script from our own inputs (`tools/generate_corpus.py`, or a generator next to the package's tests).
2. **Published** by others for their own purposes (open textbooks, specification samples, test suites), under a licence that lets us use it. If the licence allows redistribution, the file MAY be committed. Otherwise `tools/fetch_corpus.sh` downloads it from a pinned URL checked by SHA-256.
3. **Made by a contributor** with an app they are licensed to use, when they own the result, release it under a compatible licence, and it contains no personal data or third-party assets.

Each file's source, licence and how it was obtained MUST be recorded in `test_corpus/MANIFEST` (or the package's fixture notes) in the same change. You MUST NOT commit a file from anyone's disk that is not one of the three.
