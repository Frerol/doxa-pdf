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
 * True when a persisted grant on [grantUri] lets the app open [documentUri]:
 * the same URI, or a document reached through that granted folder tree
 * (`content://authority/tree/<id>/document/<doc>`). Library folders hold one
 * grant for the whole tree, not one per file (FR-FILE-006).
 */
internal fun grantCovers(grantUri: String, documentUri: String): Boolean =
    grantUri == documentUri ||
        ("/tree/" in grantUri && documentUri.startsWith("$grantUri/document/"))

/** True for entries a library folder lists: subfolders and PDFs. */
internal fun isListed(mime: String?, name: String): Boolean =
    mime == Document.MIME_TYPE_DIR || isPdfMime(mime) || name.endsWith(".pdf", ignoreCase = true)

/** Folder trees granted by the user; provider queries run on a worker. */
internal class LibraryFolders(context: Context) {
    private val resolver = context.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Keeps read and write access to a tree the folder picker returned. */
    fun persist(tree: Uri, flags: Int): PlatformFolder {
        val modes = flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            resolver.takePersistableUriPermission(tree, modes)
        } catch (error: SecurityException) {
            // Read access is enough to browse and open; renaming needs write.
            if (modes == Intent.FLAG_GRANT_READ_URI_PERMISSION) throw error
            resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val root = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        val name = runCatching {
            resolver.query(root, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull()
        return PlatformFolder(tree.toString(), name?.takeIf { it.isNotBlank() } ?: rootId)
    }

    fun list(treeUri: String, documentId: String?, callback: (Result<List<PlatformFolderEntry>>) -> Unit) {
        worker.execute {
            val result = runCatching { query(Uri.parse(treeUri), documentId) }.recoverCatching { error ->
                throw when (error) {
                    is FlutterError -> error
                    is SecurityException -> FlutterError("permissionLost")
                    is FileNotFoundException, is IllegalArgumentException -> FlutterError("missing")
                    else -> FlutterError("unreadable")
                }
            }
            main.post { callback(result) }
        }
    }

    private fun query(tree: Uri, documentId: String?): List<PlatformFolderEntry> {
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isReadPermission }) {
            throw FlutterError("permissionLost")
        }
        val parent = documentId ?: DocumentsContract.getTreeDocumentId(tree)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )
        val cursor = resolver.query(children, columns, null, null, null)
            ?: throw FlutterError("missing")
        return cursor.use {
            val entries = ArrayList<PlatformFolderEntry>(it.count)
            while (it.moveToNext()) {
                val id = it.getString(0) ?: continue
                val name = it.getString(1)?.takeIf { n -> n.isNotBlank() } ?: continue
                val mime = it.getString(2)
                // Hidden files and folders, as file managers hide them.
                if (name.startsWith(".") || !isListed(mime, name)) continue
                val directory = mime == Document.MIME_TYPE_DIR
                entries += PlatformFolderEntry(
                    documentId = id,
                    uri = DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                    name = name,
                    isDirectory = directory,
                    size = if (directory || it.isNull(3)) null else it.getLong(3),
                    lastModified = if (it.isNull(4)) null else it.getLong(4),
                )
            }
            entries
        }
    }

    fun release(treeUri: String) {
        val tree = Uri.parse(treeUri)
        val grant = resolver.persistedUriPermissions.firstOrNull { it.uri == tree } ?: return
        var modes = 0
        if (grant.isReadPermission) modes = modes or Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (grant.isWritePermission) modes = modes or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { resolver.releasePersistableUriPermission(tree, modes) }
    }

    fun close() {
        worker.shutdown()
    }
}
