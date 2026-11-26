// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.zip.ZipException
import java.util.zip.ZipInputStream

/** Mime types of a dictionary `.zip` opened with "Open with" (FR-TEXT-012). */
internal val ZIP_MIMES = setOf("application/zip", "application/x-zip-compressed", "application/x-zip")

internal fun isZipMime(mime: String?): Boolean = mime?.lowercase() in ZIP_MIMES

/** Most bytes an import may write, so a zip bomb cannot fill the disk. */
internal const val MAX_IMPORT_BYTES = 2L * 1024 * 1024 * 1024

/** Most files an import may write. */
internal const val MAX_IMPORT_FILES = 4096

private val DICTIONARY_SUFFIXES = listOf(
    ".ifo", ".idx", ".idx.gz", ".dict", ".dict.dz", ".syn", ".syn.dz",
)

/**
 * True for the files a dictionary import keeps: the StarDict set and its
 * licence or read-me notes. Hidden files (macOS `._` forks too) are skipped.
 */
internal fun isDictionaryFile(name: String): Boolean {
    val lower = name.lowercase()
    if (name.startsWith(".")) return false
    return DICTIONARY_SUFFIXES.any { lower.endsWith(it) } ||
        lower.startsWith("license") || lower.startsWith("licence") ||
        lower.startsWith("readme") || lower.startsWith("copying")
}

/**
 * The relative path a zip entry may be written to, or null when it must be
 * skipped: a folder, a path that leaves the target ("../", absolute paths,
 * drive letters), or a file that is not part of a dictionary.
 */
internal fun safeEntryPath(name: String): String? {
    if (name.endsWith("/") || name.contains('\u0000')) return null
    val parts = name.replace('\\', '/').split('/').filter { it.isNotEmpty() && it != "." }
    if (parts.isEmpty() || name.startsWith("/") || parts.first().endsWith(":")) return null
    if (parts.any { it == ".." || it.startsWith(".") }) return null
    if (!isDictionaryFile(parts.last())) return null
    return parts.joinToString("/")
}

/**
 * Copies a dictionary the user picked (files, a `.zip` or a folder) into a
 * new staging folder in the cache (FR-TEXT-009). The app then validates the
 * staged sets and moves them into its dictionaries folder. Provider I/O
 * runs on a worker; results come back on the main thread.
 */
internal class DictionaryImports(context: Context) {
    private val resolver = context.contentResolver
    private val cache = context.cacheDir
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        // Imports left behind when the process died in the middle of one.
        worker.execute {
            cache.listFiles { file -> file.name.startsWith(STAGING_PREFIX) }
                ?.forEach { it.deleteRecursively() }
        }
    }

    /** Stages [uris]: each `.zip` is extracted, other files are copied. */
    fun stageFiles(uris: List<Uri>, callback: (Result<String>) -> Unit) = perform(callback) { target ->
        val budget = Budget()
        for (uri in uris) {
            val name = displayName(uri) ?: uri.lastPathSegment ?: "file"
            val zip = name.lowercase().endsWith(".zip") ||
                isZipMime(runCatching { resolver.getType(uri) }.getOrNull())
            open(uri).use { input ->
                if (zip) extract(input, target, budget) else if (isDictionaryFile(name)) {
                    copy(input, File(target, File(name).name), budget)
                }
            }
        }
    }

    /** Stages the dictionary files of a folder tree, keeping its layout. */
    fun stageTree(tree: Uri, callback: (Result<String>) -> Unit) = perform(callback) { target ->
        val root = DocumentsContract.getTreeDocumentId(tree)
        copyTree(tree, root, target, Budget(), depth = 0)
    }

    fun close() {
        worker.shutdown()
    }

    private fun perform(callback: (Result<String>) -> Unit, action: (File) -> Unit) {
        worker.execute {
            val target = File(cache, "$STAGING_PREFIX${System.nanoTime()}")
            val result = runCatching {
                if (!target.mkdirs()) throw IOException("Cannot create $target")
                action(target)
                target.absolutePath
            }.recoverCatching { error ->
                target.deleteRecursively()
                throw when (error) {
                    is FlutterError -> error
                    is SecurityException -> FlutterError("permissionLost")
                    is FileNotFoundException -> FlutterError("missing")
                    is ZipException -> FlutterError("notDictionary")
                    else -> FlutterError("unreadable")
                }
            }
            main.post { callback(result) }
        }
    }

    private fun open(uri: Uri): InputStream =
        resolver.openInputStream(uri) ?: throw FileNotFoundException(uri.toString())

    private fun extract(input: InputStream, target: File, budget: Budget) {
        ZipInputStream(input.buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.isDirectory) continue
                val path = safeEntryPath(entry.name) ?: continue
                copy(zip, File(target, path), budget)
            }
        }
    }

    private fun copyTree(tree: Uri, documentId: String, target: File, budget: Budget, depth: Int) {
        if (depth > 8) return
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE)
        val entries = ArrayList<Triple<String, String, String?>>()
        val cursor = resolver.query(children, columns, null, null, null)
            ?: throw FileNotFoundException(children.toString())
        cursor.use {
            while (it.moveToNext()) {
                val id: String = it.getString(0) ?: continue
                val name: String = it.getString(1) ?: continue
                val mime: String? = it.getString(2)
                entries.add(Triple(id, name, mime))
            }
        }
        for ((id, name, mime) in entries) {
            if (name.startsWith(".") || name.contains('/')) continue
            if (mime == Document.MIME_TYPE_DIR) {
                copyTree(tree, id, File(target, name), budget, depth + 1)
            } else if (isDictionaryFile(name)) {
                open(DocumentsContract.buildDocumentUriUsingTree(tree, id)).use {
                    copy(it, File(target, name), budget)
                }
            }
        }
    }

    /** Copies [input] to [file], within the import's [budget]. */
    private fun copy(input: InputStream, file: File, budget: Budget) {
        if (++budget.files > MAX_IMPORT_FILES) throw FlutterError("tooLarge")
        file.parentFile?.mkdirs()
        file.outputStream().use { output ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                budget.bytes += read
                if (budget.bytes > MAX_IMPORT_BYTES) throw FlutterError("tooLarge")
                output.write(buffer, 0, read)
            }
        }
    }

    private fun displayName(uri: Uri): String? = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }.getOrNull()

    private class Budget {
        var bytes = 0L
        var files = 0
    }

    companion object {
        private const val STAGING_PREFIX = "doxa-dictionary-import-"
    }
}
