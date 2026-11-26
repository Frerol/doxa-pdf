// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/**
 * The document ID of the folder that holds the last document of [path], a
 * path from a tree's root as `DocumentsContract.findDocumentPath` returns it;
 * null when the document is the root itself.
 */
internal fun parentInPath(path: List<String>): String? =
    if (path.size < 2) null else path[path.size - 2]

/** Maps a provider failure to the error codes the Dart side knows. */
internal fun fileActionError(error: Throwable): FlutterError = when (error) {
    is FlutterError -> error
    is SecurityException -> FlutterError("permissionLost")
    is FileNotFoundException -> FlutterError("missing")
    is UnsupportedOperationException -> FlutterError("unsupported")
    else -> FlutterError("failed")
}

/**
 * Renames, moves and deletes documents through their providers (FR-FILE-011).
 * Provider calls run on a worker; results come back on the main thread.
 */
internal class DocumentFiles(context: Context) {
    private val resolver = context.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun rename(uri: String, displayName: String, callback: (Result<PlatformMovedDocument>) -> Unit) =
        perform(callback) {
            val source = Uri.parse(uri)
            requireSupport(source, Document.FLAG_SUPPORTS_RENAME)
            // Providers that keep the document ID return null.
            val renamed = DocumentsContract.renameDocument(resolver, source, displayName) ?: source
            located(renamed)
        }

    fun move(
        uri: String,
        targetTreeUri: String,
        targetDocumentId: String?,
        callback: (Result<PlatformMovedDocument>) -> Unit,
    ) = perform(callback) {
        val source = Uri.parse(uri)
        val targetTree = Uri.parse(targetTreeUri)
        // Providers move only between their own folders.
        if (!DocumentsContract.isTreeUri(source) || source.authority != targetTree.authority) {
            throw FlutterError("unsupported")
        }
        requireSupport(source, Document.FLAG_SUPPORTS_MOVE)
        val path = DocumentsContract.findDocumentPath(resolver, source)?.path
            ?: throw FlutterError("unsupported")
        val parentId = parentInPath(path) ?: throw FlutterError("unsupported")
        val parent = DocumentsContract.buildDocumentUriUsingTree(source, parentId)
        val targetId = targetDocumentId ?: DocumentsContract.getTreeDocumentId(targetTree)
        if (targetId == parentId) return@perform located(source)
        val target = DocumentsContract.buildDocumentUriUsingTree(targetTree, targetId)
        val moved = DocumentsContract.moveDocument(resolver, source, parent, target)
            ?: throw FlutterError("failed")
        // The provider builds the new URI on the source tree; the document
        // now lies in the target tree, whose grant covers it.
        val movedId = DocumentsContract.getDocumentId(moved)
        located(DocumentsContract.buildDocumentUriUsingTree(targetTree, movedId))
    }

    fun delete(uri: String, callback: (Result<Unit>) -> Unit) = perform(callback) {
        val source = Uri.parse(uri)
        requireSupport(source, Document.FLAG_SUPPORTS_DELETE)
        if (!DocumentsContract.deleteDocument(resolver, source)) throw FlutterError("failed")
        // A grant on the file alone is of no use any more.
        releaseGrant(source)
    }

    fun close() {
        worker.shutdown()
    }

    private fun <T> perform(callback: (Result<T>) -> Unit, action: () -> T) {
        worker.execute {
            val result = runCatching(action).recoverCatching { throw fileActionError(it) }
            main.post { callback(result) }
        }
    }

    /** Fails with `missing` or `unsupported` before asking the provider. */
    private fun requireSupport(uri: Uri, flag: Int) {
        val flags = resolver.query(uri, arrayOf(Document.COLUMN_FLAGS), null, null, null)?.use {
            if (it.moveToFirst()) it.getInt(0) else throw FlutterError("missing")
        } ?: throw FlutterError("missing")
        if (flags and flag == 0) throw FlutterError("unsupported")
    }

    /** Where [uri] is now: its name and whether a lasting grant covers it. */
    private fun located(uri: Uri): PlatformMovedDocument {
        val target = uri.toString()
        var persisted = resolver.persistedUriPermissions.any {
            it.isReadPermission && grantCovers(it.uri.toString(), target)
        }
        if (!persisted) {
            // A renamed single file gets a new grant only for this run.
            val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
            persisted = listOf(read or Intent.FLAG_GRANT_WRITE_URI_PERMISSION, read).any { modes ->
                runCatching { resolver.takePersistableUriPermission(uri, modes) }.isSuccess
            }
        }
        val name = runCatching {
            resolver.query(uri, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull()
        return PlatformMovedDocument(target, name?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment ?: "PDF", persisted)
    }

    private fun releaseGrant(uri: Uri) {
        val grant = resolver.persistedUriPermissions.firstOrNull { it.uri == uri } ?: return
        var modes = 0
        if (grant.isReadPermission) modes = modes or Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (grant.isWritePermission) modes = modes or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { resolver.releasePersistableUriPermission(uri, modes) }
    }
}
