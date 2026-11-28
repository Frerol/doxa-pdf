# doxa_platform

Flutter plugin for platform features Flutter lacks: Android Storage Access Framework, "Open with" intents, and the low-latency stylus surface. Uses [pigeon](https://pub.dev/packages/pigeon) for typed platform messages (`pigeon/messages.dart`).

Part of the [Doxa PDF](../../README.md) workspace. See [architecture §2](../../docs/plan/03-architecture.md#2-repository-layout).

## Saving PDFs on Android

Use `DoxaPlatform().pdfSaves.canWrite(uri)` before editing. It checks for a
persisted write grant (including a library tree grant) and the provider's
document flags without opening a write stream. Offer Save a copy when the
check returns false.

Pass the engine-verified cache file to `writeBack(uri, tempPath)`. The plugin
backs up the current URI contents in the cache, opens the URI with `wt`, and
reads it back after closing the output stream to verify its SHA-256. SAF
providers can truncate or modify the URI before verification succeeds.
If writing or verification fails, `PdfSaveException.recoveryPath` points
to the backup of the previous bytes so the caller can export or restore them.
Handle recovery before the cache can be evicted and delete the backup when
it is no longer needed. A failure before taking a complete backup leaves the
URI untouched. A successful write-back removes its backup.

Both `writeBack` and `saveCopy` leave the source file in place. Keep it unchanged
until the operation completes, and retain it after an error for retry or
export. `saveCopy` uses Android's document picker and returns the destination
URI after verification, or null on cancellation. A failed export can leave an
incomplete file at the chosen destination. Pass a readable PDF content URI
(such as the URI returned by `saveCopy`) to `share` to open the system share
sheet with a temporary read grant.
