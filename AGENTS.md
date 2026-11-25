# AGENTS.md

Instructions for coding agents (OpenAI Codex and others) working on Doxa PDF. Claude Code reads `CLAUDE.md`, which has the same rules.
When you change a rule here, update `CLAUDE.md` too.

## 1. Project in one minute
Doxa PDF is a free (GPL-3.0-or-later) PDF reader **for studying** on Android, Windows and Linux. The core features are **text markup**
(highlight, underline, squiggly) and **pen annotation** with the S Pen. The MVP is **Android-only** (betas v0.1–v0.4 on GitHub Releases), and Linux comes next.

- Plan: `docs/README.md` (index), especially `docs/plan/11-mvp.md` (MVP scope), `02-requirements.md` (IDs like `FR-INK-002`) and `08-roadmap.md`.
- Decisions: `docs/adr/`. Spike reports with measurements: `docs/spikes/`. **Read the relevant ones before designing anything.**
- The maintainer (GitHub `Frerol`) speaks **Brazilian Portuguese**. Talk to them in pt-BR. Code, comments, docs, commits, issues and PRs are in **English**.

## 2. Current status (update this section when it changes)
- **M0 (foundations and spikes), almost done.** Done: monorepo scaffold, PDFium bindings, Spike A (rendering, ADR-0005), Spike B (ink, ADR-0006),
  Spike C (annotation writing, ADR-0008), tasks T-01..T-10 (`doxa_core` geometry/dates/IDs/page transforms/palette, `doxa_ink` pressure/smoothing/simplification/erasing),
  #9 PDF test corpus (PR #33), #3 full CI with Android APK and dependency license checks (PR #34), and #8 Spike D (OCR: GO with
  Tesseract4Android, `docs/spikes/D-ocr.md`; ADR-0007 proposed, awaiting the maintainer's acceptance).
- **Open:** #10 Code of Conduct contact (maintainer only), #11 M0 wrap-up. Specs are in §8.
  Branch protection on `main` is still to be enabled by the maintainer (required checks listed in PR #34).
- **Next:** M1 = v0.1 Reader (§9).

## 3. Repository layout
| Path | What | Tests |
|---|---|---|
| `app/` | Flutter app (Android; applicationId `io.github.frerol.doxapdf`, minSdk 29) | `flutter test` |
| `packages/doxa_core` | Pure Dart domain: geometry, page transforms, dates, IDs, palette. **No Flutter imports** (enforced by a test) | `dart test` |
| `packages/doxa_dict` | Pure Dart offline dictionary support (StarDict metadata parser) | `dart test` |
| `packages/doxa_ink` | Pure Dart ink: pressure curve, arc smoothing, resampling, hit testing, partial erase | `dart test` |
| `packages/doxa_engine` | PDF engine on PDFium (today: a temporary engine check) | `dart test` (needs PDFium) |
| `packages/pdfium_ffi` | ffigen-generated PDFium bindings + `openPdfium()` loader | `dart test` (needs PDFium) |
| `packages/doxa_platform` | Android plugin (pigeon) | `flutter test` |
| `tools/` | `check.sh`, `fetch_pdfium.sh`, `pdfium.lock`, `fetch_corpus.sh`, `generate_corpus.py`, dependency license checks | `python3 -m unittest` |
| `test_corpus/` | Small license-cleared PDF fixtures, `MANIFEST` (source + license per file); large files fetched into git-ignored `external/` | used by `pdfium_ffi` tests |
| `spike/*` branches | Throwaway prototypes (`ink_lab`, `annot_write`, `saf_lab`, `render_probe`, `render_lab`). **Reuse their code as a reference; never merge them** | — |

## 4. Environment (maintainer's machine)
- Flutter **3.50.1** via FVM: `export PATH="$HOME/fvm/default/bin:$PATH"` (or `.fvm/flutter_sdk/bin`). JDK 17: `export JAVA_HOME=$HOME/.local/share/jdk/17`.
  Android SDK: `export ANDROID_HOME=$HOME/Android/Sdk`, `adb` at `$ANDROID_HOME/platform-tools/adb`.
- PDFium binaries are git-ignored: run `tools/fetch_pdfium.sh` (all), or `linux`/`android` only. The Android build fails early with a clear message if they are missing.
- **Reference device:** Galaxy Tab S10 FE (SM-X520), Android 16, 90 Hz, S Pen, usually on USB as serial `RXGL20545MJ`. Install and run with
  `cd app && flutter run --profile -d RXGL20545MJ` (use **profile** builds for any performance measurement, never debug). Read logs with `adb logcat -s flutter`.
  You cannot see the screen. Ask the maintainer to try things and describe what they see. Never take screenshots without asking.
- `/tmp` is a **small RAM disk**. Never copy SDKs, caches or the repo there to get around a sandbox restriction: if a command is blocked (writes outside
  the workspace, network, git metadata), stop and report which command failed and why. Clean up temporary files before finishing.

## 5. Commands
```sh
tools/fetch_pdfium.sh linux          # pinned PDFium for native tests
flutter pub get                      # whole pub workspace, from the repo root
tools/check.sh                       # format + analyze + all tests (with coverage); must pass before any PR
python3 tools/check_dependency_licenses.py pub   # pub license check (CI also runs it, plus a Gradle check after the APK build)
tools/fetch_corpus.sh                # large test PDFs into test_corpus/external/ (needs curl, sha256sum, Ghostscript)
cd app && flutter build apk --debug  # Android build
cd packages/pdfium_ffi && dart run tool/ffigen.dart   # regenerate bindings (only when headers change)
cd packages/doxa_platform && dart run pigeon --input pigeon/messages.dart && dart format .   # regenerate platform messages
```

## 6. Git, PRs and GitHub
- Never push to `main` and **never merge PRs**. The maintainer approves every merge, and may ask you to merge after approving.
- Branch names: `feat/…`, `fix/…`, `docs/…`, `chore/…`, `spike/…`. Conventional Commits, signed off (`git commit -s`), ending with
  `Co-Authored-By: Codex <noreply@openai.com>`.
- **Pushing:** the SSH key needs a passphrase, so push over HTTPS with the GitHub CLI token:
  `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u https://github.com/Frerol/doxa-pdf.git <branch>`
- Open PRs with `gh pr create --repo Frerol/doxa-pdf --base main`. Give each a milestone (`M0 — Foundations & spikes`, `M1 — v0.1 Reader`, …) and labels
  (`type:*`, `area:*`, `platform:*`). Reference requirement IDs and use `Closes #n`. Wait for CI (`gh pr checks <n> --watch`) and report the result.
- One issue per PR. Keep PRs small. Never use `git add -A` blindly: check `git status` (agent worktrees under `.claude/worktrees/` must never be committed).
- Avoid chaining destructive commands with `;` after commands that may fail (a failed step must stop the chain).

## 7. Rules and hard-won pitfalls
**General**
- English everywhere in the repo. SPDX header `// SPDX-License-Identifier: GPL-3.0-or-later` on every source file. Strict lints, so `dart format` and `flutter analyze` must be clean.
- Tests for every change, and a regression test for every bug fix. Requirement IDs are stable: never renumber them.
- Dependencies must be GPL-3.0-compatible. **Ask before adding any dependency.** No Google ML Kit or other proprietary SDKs.
- **Never name the commercial PDF reader that inspired Doxa** anywhere (code, docs, commits, issues, PRs). Write "a commercial PDF reader".
  The UI should resemble the leading commercial mobile readers in **layout and flows**, with an original identity (`docs/plan/05-ux-design.md` §8).
- Significant decisions need an ADR (`docs/adr/0000-template.md`). The next free number is 0010.
- Do not edit generated files by hand (`pdfium_bindings.g.dart`, `messages.g.*`, `app/lib/l10n/gen/`), `tools/pdfium.lock`, accepted ADRs, or `LICENSE`.

**Flutter 3.50**
- Import `package:material_ui/material_ui.dart`, **not** `package:flutter/material.dart` (deprecated).
- Localization: use `[AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]` (from material_ui). The gen-l10n list breaks `pt`.
  New strings go to both `app/lib/l10n/app_en.arb` and `app_pt.arb`.
- `Isolate.run` closures must capture only sendable values: build them in a top-level function that takes plain arguments (capturing `this`/State fails).
- `CustomPainter`: never `canvas.drawColor` without `clipRect`, because it paints the whole screen.

**PDFium (ADR-0005, 0006, 0008)**
- All PDFium calls run in **one engine isolate**. PDFium is not thread-safe.
- **Two document instances per file:** a read-only *render instance* (Doxa's own annotations hidden in memory via the Hidden flag, rendered with
  `FPDF_ANNOT`) and an *editing instance* (never rendered with `FPDF_ANNOT`; the only one saved).
- **Saving:** `FPDF_SaveAsCopy` **full save** (flags 0) → temp file → verify → atomic replace. **Never `FPDF_INCREMENTAL`**: it bloats files and corrupts xref-stream PDFs.
  On Android, write back through SAF with `"wt"` and verify by reading back (SHA-256).
- Text markup is written **without `/AP`**. Ink AP comes from page objects via `FPDFAnnot_AppendObject`, called **after every other setter**
  (`FPDFAnnot_SetBorder` deletes an existing AP, and `FPDFAnnot_SetColor` fails once an AP exists).
- `FPDF_BOOL` is an `int` (0 = false). Strings to PDFium are UTF-16LE (`toNativeUtf16`). Free every native allocation.
- ffigen 23 uses a Dart config (`tool/ffigen.dart`): declarations are excluded by default, `-resource-dir` (not `-isystem`) for clang builtins, and leading underscores stripped from struct names.

**Ink (ADR-0006)**
- Pure Flutter, raw `Listener`. Live stroke as vectors on its own layer; committed ink rasterized into tiles (never replay all vectors every frame).
- No smoothing by default; optional arc-length smoothing (2–4 px); **never a One-Euro filter**. S Pen side button = `kPrimaryStylusButton` → eraser.
- Pan/zoom through a `ValueNotifier` (repaint) instead of `setState` (rebuild).
- **Stylus pointers must never reach pan/zoom recognizers** (`InteractiveViewer`, scrollables). Disabling pan after the pen's pointer-down is too late:
  the recognizer has already joined the gesture arena and the page shifts a little under the pen (seen in Spike D's harness).

## 8. Next tasks (M0)
Work on them in this order, one PR each. #9 (test corpus), #3 (full CI) and #8 (Spike D) are done.

### #8 · Spike D: on-device OCR (needs the tablet)
Goal: make scanned pages searchable and highlightable (FR-UTIL-001, NFR-PERF-009: ≤ 5 s per page on the reference tablet, in the background, cancellable).
1. Prototype on branch `spike/ocr` (a small app like `spike/render:spikes/render_lab`). Use **Tesseract** (Apache-2.0) through a maintained Android binding or
   an FFI build. Compare the options and check licenses. Models: `tessdata_fast` **por** + **eng**, downloadable on demand.
2. Write an **invisible text layer** with PDFium: `FPDFText_LoadStandardFont`, `FPDFPageObj_NewTextObj`, `FPDFText_SetText`,
   `FPDFTextObj_SetTextRenderMode(FPDF_TEXTRENDERMODE_INVISIBLE)`, `FPDFPageObj_Transform` (position and size from each word box), `FPDFPage_InsertObject`,
   `FPDFPage_GenerateContent`, then a full save. Afterwards, check that `FPDFText_*` search and selection boxes line up with the words in the image.
3. Measure on the tablet: time per page, memory, model and APK size. Test with `test_corpus/scanned-300.pdf` and `test_corpus/external/scanned-chapter.pdf` (from `tools/fetch_corpus.sh`).
4. Deliver `docs/spikes/D-ocr.md` (method, numbers, go/no-go) and **ADR-0007** (OCR integration approach) on `main` via a docs PR. Never merge the spike code.

### #11 · M0 wrap-up
After #8: update `docs/plan/09-risks.md` (R13 OCR, R14 memory), the roadmap if scope changed, and `docs/README.md`; then create the **M1 issues** (one per
coherent feature slice, referencing requirement IDs from `08-roadmap.md` M1), each with tasks and acceptance criteria, in milestone `M1 — v0.1 Reader`.

## 9. Guide for M1 (v0.1 Reader)
Scope: `docs/plan/11-mvp.md` §3 v0.1 and `08-roadmap.md` M1. Suggested order (each a separate PR, behind tests):
1. **`doxa_engine` production engine** from `spike/render:spikes/render_lab/lib/engine.dart`: a typed request/response protocol instead of maps,
   a priority queue with generation cancellation, the render/edit instance split (ADR-0005), page sizes, outline, text, search. Unit tests with the PDFium fixture.
2. **Reader view** in `app/`: continuous vertical layout first, previews + 512 px tiles + LRU cache, pinch zoom and fling (from `render_lab/lib/main.dart`),
   then single page, two pages and horizontal layouts. Add `onTrimMemory` handling and keep RSS under 400 MB on scanned books.
3. **Opening files:** SAF picker and "Open with" intents through `doxa_platform` (pigeon; see `spike/annot-write:spikes/saf_lab` for the Kotlin side),
   then recents with progress, library folders and tabs.
4. Navigation panels (outline, thumbnails), search, night/sepia, and pt-BR + en strings.
5. **Offline dictionary** (FR-TEXT-008..010, ADR-0009): `packages/doxa_dict` first (tasks T-11..T-15 in §11), then import/settings and the lookup popup in `app/`.
Before coding a slice, write its issue (if missing) and keep the UI **familiar and original** (§7).

## 10. When to stop and ask the maintainer
Anything that needs the physical tablet (S Pen feel, visual checks), UI/UX choices not covered by `05-ux-design.md`, new dependencies, licensing questions,
ADR-level decisions, releases/store/signing, the Code of Conduct contact (#10), or any destructive git operation (force-push to shared branches, history rewrites, deleting branches you did not create).

## 11. Task queue for agents
Well-specified, pure Dart tasks for coding agents. **One task per PR**, titled `<type>(<package>): … (T-xx)`, on a branch `feat/<topic>`.
Tasks run in order; each says what it depends on. The maintainer ticks them in "Completed agent tasks" after the merge.

**T-11..T-15 implement `packages/doxa_dict` (FR-TEXT-008..010, [ADR-0009](docs/adr/0009-offline-dictionary.md)). ADR-0009 is accepted; start with T-11.**
Rules for all of them: pure Dart (no Flutter imports; add a dependency-rule test like `doxa_core`'s), **no new dependencies** (`dart:io` zlib is enough),
SPDX headers, `dart test` from the package dir, small fixtures under `test/fixtures/` produced by a committed generator, and malformed-input tests
(truncated files, wrong sizes, bad UTF-8) that must throw a typed `DictionaryFormatException`, never crash or hang.

### T-11 · Package scaffold and `.ifo` parser
Create `packages/doxa_dict` (workspace member, `analysis_options.yaml` like the other packages) and `StarDictInfo.parse(List<int> bytes)`:
- Decode strictly as UTF-8 (bad bytes → `DictionaryFormatException`). Accept LF, CRLF and CR line endings and skip blank lines.
- The first line must be `StarDict's dict ifo file`, and the first key after it must be `version` (`2.4.2` or `3.0.0`). Split each line at the **first** `=`.
- Required: `bookname`, `wordcount`, `idxfilesize`. Optional: `synwordcount`, `idxoffsetbits` (32 or 64; only valid with `3.0.0`; default 32),
  `sametypesequence`, `author`, `email`, `website`, `description`, `date`, `dicttype`. Every other key (for example `lang`) goes to an `extra` map.
- Tests for every key, defaults, line endings and each error.

### T-12 · `.idx` and `.syn` index (depends on T-11)
- `.idx` (or gzip-compressed `.idx.gz`, decompressed with a size bound): entries are a UTF-8 headword ending in `\0`, an unsigned big-endian offset
  of `idxoffsetbits` bits and an unsigned big-endian 32-bit size. `idxfilesize` is compared with the **decompressed** byte count and the entry count with `wordcount`.
- `.syn`: a UTF-8 alias ending in `\0` and an unsigned big-endian 32-bit **zero-based ordinal** into `.idx`. If `.syn` exists, `synwordcount` is required
  and must match; ordinals out of range are errors. Duplicate aliases pointing to different entries are all kept.
- Both files must be sorted in StarDict order: `g_ascii_strcasecmp`, ties broken by a byte-wise `strcmp`. Validate the order on load and binary-search over it.
- Tests: exact hits, case-only differences, first/last entries, duplicate headwords, synonyms, 64-bit offsets, `.idx.gz`, unsorted and truncated files.

### T-13 · `.dict` and dictzip reader (depends on T-11)
- Random-access reads of `(offset, size)` from a plain `.dict` and from dictzip `.dict.dz`.
- Dictzip layout: inside the gzip `FEXTRA` field, the `RA` subfield has a little-endian 16-bit length, then unsigned little-endian 16-bit values for
  version (`1`), the nominal uncompressed chunk length, the chunk count, and each compressed chunk size. Compressed data starts after the **full** gzip header
  (`FEXTRA`, `FNAME`, `FCOMMENT`, `FHCRC`). Validate the table against the file size, inflate only the chunks a range needs with `ZLibDecoder(raw: true)`,
  check each inflated length (the last chunk may be shorter), and keep a small LRU of chunks.
- Field framing: lowercase types are text ending in `\0`; uppercase types are binary, prefixed by an unsigned big-endian 32-bit length.
  Without `sametypesequence`, each field starts with its type byte. With it, type bytes are omitted and the **last** field takes the remaining bytes of the
  entry, with neither its `\0` nor its length prefix.
- Fixtures: a dictzip file made by a committed generator that reproduces `dictzip` (one gzip member, `Z_FULL_FLUSH` at each chunk boundary; Python's `zlib` is fine),
  plus mixed text/binary entries in both framings. Tests: ranges inside one chunk, across chunks, at the end of the file; plain and dictzip give identical bytes.

### T-14 · `Dictionary` facade and lookup normalization (depends on T-12, T-13)
- `Dictionary.open(File ifo)` loads the companion files sharing the `.ifo` basename (`.idx` before `.idx.gz`, `.dict` before `.dict.dz`, optional `.syn`)
  and exposes `info`. `Dictionary.findAll(Directory dir)` lists every valid `.ifo` set in a directory tree and reports the invalid ones with their error.
- `lookup(String query) → List<DictionaryEntry>` (headword, ordinal, raw fields) per FR-TEXT-010. Trim surrounding whitespace and punctuation, then try, in order,
  stopping at the first level that has results: (1) exact headword, (2) case-folded, (3) case- and diacritic-folded. At each level, direct `.idx` hits and `.syn`
  aliases are merged, deduplicated by ordinal and returned in `.idx` order.
- Folding uses a **secondary normalized index** built lazily on the first folded lookup (normalized key → ordinals), not a scan per query. Case folding is
  `toLowerCase()`; diacritic folding removes combining marks U+0300–U+036F after decomposing Latin-1 Supplement and Latin Extended-A letters with a small built-in table
  (no new dependencies). Composed and decomposed "ação" must both find "acao" and vice versa.
- `suggest(String query, {int limit = 10})` returns headwords with the longest shared normalized prefix, in `.idx` order.
- Everything synchronous and isolate-friendly (plain arguments, no closures over state), so the app can run it with `Isolate.run`.

### T-15 · Safe definition text (depends on T-13)
Convert a field to a small immutable rich-text model (`DefinitionBlock`/`DefinitionSpan`: paragraph, list item, line break, bold, italic).
- `m`, `t`, `y`: plain text (newlines → line breaks). `g` (Pango markup): tags stripped to plain text.
- `h` (HTML): keep `p`, `br`, `b`/`strong`, `i`/`em`, `ul`/`ol`/`li`. Discard `script` and `style` **with their content**; keep the visible text of links and every other tag.
- `x` (XDXF): `k` → bold paragraph, `b` → bold, `i` and `ex` → italic, `abr` → italic, `c`, `kref`, `dtrn`, `co` → plain text, `blockquote` → paragraph; other tags keep their text.
- Entities: the five XML ones, decimal and hex numeric references, and `nbsp`, `ndash`, `mdash`, `hellip`, `laquo`, `raquo`, `copy`; unknown entities stay literal.
- Other types (binary, unknown) are skipped and counted as `unsupportedFields`, so the entry still shows its supported fields. Never fetch anything.
- Tests with hostile input (`<script>`, unclosed tags, deep nesting, huge entities), and separately: script/style bodies dropped, link text kept.

## Completed agent tasks
T-01..T-10 (PRs #19–#28): PDF dates, annotation UUIDs, geometry, page transforms, study palette, pressure curve, arc smoothing, resampling/RDP,
hit testing and partial erase, Dependabot. Their specs are in git history (`git log -p -- AGENTS.md`).
