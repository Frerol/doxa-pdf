# ADR-0013 — Annotation journal and autosave

- **Status:** Proposed
- **Date:** 2026-11-28

## Context

Annotations live inside the PDF ([ADR-0008](0008-annotation-save-strategy.md)). Between two saves they exist only in memory: in the reader's
`AnnotationStore` and in the engine's editing instance. A crash, an app kill or a failed save must not lose them. NFR-REL-001 allows losing at
most the stroke in progress, and FR-SAVE-003 asks for a journal of unsaved operations that is replayed at the next launch. FR-SAVE-001 asks
for autosave into the original file, or "ask on close" instead.

Edits are already small, serialisable, invertible commands (`AnnotationCommand`, #144). The undo history, the engine sync and the journal
were meant to share them ([03 — Architecture §5](../plan/03-architecture.md#5-annotation-data-flow)). The planned home is a `journal` table
in the drift database ([§7](../plan/03-architecture.md#7-persistence)).

Two facts shape the design:

- **Identity changes on save.** A document's identity is a hash of its size and first and last 64 KB (`document_identity.dart`). Saving
  annotations rewrites the file, so the identity changes with every save. The saver must update it.
- **The file can change without us.** Another app, a sync client or the user can edit or replace the file between our session and the next
  launch. A journal replayed blindly onto a different file could put annotations in the wrong place.

## Decision

### Format

The journal has two drift tables, added by a schema migration:

- `journal_sessions`: one row per document with unsaved edits. It holds the location (the SAF URI on Android, the path on desktop), the
  **base identity** (the identity of the file the edits were made on), the display name, when it started and a `format` version (1).
- `journal_entries`: the applied commands of a session, in order. It holds the session id, a sequence number and the command as
  `AnnotationCommand.toJson()` text. Entries are deleted with their session.

The journal is a **log of applied commands**. An undo or redo is written as the command it applies: the inverse, or the command again. So
replaying all entries in order rebuilds the state at the crash, whatever the undo history looked like. The undo history itself is not
restored.

### When entries are written and cleared

1. A finished step goes to the journal **before** it is sent to the engine: a stroke when the pen lifts, a markup, an edit, a delete, an
   undo or a redo. A grouped step (a lasso drag) is written once when its group closes. The reader's store changes at once, so the screen
   never waits for the database. The window between the screen and the journal is one asynchronous SQLite insert, a few milliseconds.
2. The first entry of a document opens its session with the identity of the file as it is on disk.
3. **A successful, verified save** (ADR-0008, with the SAF read-back of #143) deletes the session in the same transaction that stores the
   document's new identity. A failed save keeps it.
4. Discarding changes ("Discard" in the recovery prompt) deletes the session.

SQLite runs in WAL mode with `synchronous = NORMAL`, which survives a process crash or kill. A power loss can lose the last entries; that is
accepted.

### Autosave (FR-SAVE-001)

- **Autosave** is the default: the document saves after 5 s without a new step, when the app goes to the background
  (`AppLifecycleState.hidden`/`paused`), and when its tab closes. A save never runs while a stroke or a grouped step is in progress.
- **Ask on close** is a setting: there is no timed or background save. Closing a tab with unsaved changes asks Save, Discard or Cancel. The
  journal still protects the changes until then.
- A document that cannot be written (#143, `canWrite` false) is not autosaved. The reader offers "Save a copy". Its journal stays until the
  copy is saved or the changes are discarded.

### Recovery

At launch, each session with entries is a document with **unsaved changes**. Its library row is marked. Opening it, or tapping the mark,
asks **Restore changes** or **Discard**.

- **Same file** (the identity on disk equals the base identity): restoring applies the entries in order to the engine and the store, as one
  undo step, so the user can undo the whole restore. The document then counts as unsaved, and autosave saves it as usual.
- **Changed file** (another identity): the prompt says the file changed since the edits and asks before restoring. Restoring then
  applies each entry only where it still fits. An add whose ids are already on the page is skipped, since an earlier save may have succeeded
  before its session was cleared. A change or delete applies only if the annotation still matches the command's "before" state, as
  `AnnotationStore.apply` already checks. Skipped entries are counted, and the prompt reports how many could not be restored.
- **File gone or permission lost:** the session stays. The prompt offers to locate the file again (#143) or to discard. Nothing is
  deleted without the user's choice.

## Consequences

- No annotation is lost to a crash or kill except the stroke in progress (NFR-REL-001), and a crash in PDFium (R3) does not lose journaled
  edits (NFR-REL-002).
- The undo history, the journal and the engine sync use one command type. A change to the command JSON needs a `format` bump, and old
  sessions need a reader or an explicit discard prompt.
- The journal holds annotation contents (notes, highlighted text) in plain text in the app's private database, also for password-protected
  PDFs. That matches what the library already stores and stays inside the app sandbox.
- Big ink sessions write tens of kilobytes per stroke at most. A session is short-lived, because every successful save deletes it.
- Follow-up: the save coordinator (autosave timer, lifecycle hooks, identity update) and the recovery prompt UI are implemented in #145.
  The prompt wording and the library mark need the maintainer's approval as UI.

## Alternatives considered

- **Snapshot the whole annotation state** instead of a command log: replaying is trivial, but each step rewrites every annotation of the
  document, which is large for ink, and it cannot tell which edits still fit a changed file.
- **Journal the undo history** (undo and redo stacks) instead of applied commands: it restores undo across a crash, but recovery becomes a
  state machine and must be kept in step with the history's cap and groups. Applied commands keep replay a plain loop.
- **Incremental saves into the PDF as the journal** (`FPDF_INCREMENTAL`): ADR-0008 rejects incremental saves, which bloat files and break
  xref-stream PDFs.
- **A sidecar file next to the PDF:** it needs write access where the PDF lives, which SAF often does not give, and it can be lost or
  synced separately from the PDF.
