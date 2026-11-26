// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.Closeable
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors

internal const val PDF_MIME = "application/pdf"

/** Prefix of fallback copies in the cache directory. */
private const val CACHE_PREFIX = "doxa-pdf-"

internal fun isPdfMime(mime: String?): Boolean = PDF_MIME.equals(mime, ignoreCase = true)

internal fun isContentUri(scheme: String?, authority: String?): Boolean =
    scheme == "content" && !authority.isNullOrEmpty()

internal fun persistableModes(flags: Int): Int {
    if (flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION == 0 ||
        flags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) return 0
    return flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
}

/** Owns sources on the main thread; provider I/O and copies run on a worker. */
internal class PdfFiles(private val context: Context) {
    private val resolver = context.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val leases = mutableMapOf<Long, Source>()
    private var nextId = 0L
    private var closed = false

    init {
        // Copies left behind when the process died with a document open.
        worker.execute {
            context.cacheDir.listFiles { file -> file.name.startsWith(CACHE_PREFIX) }
                ?.forEach { it.delete() }
        }
    }

    fun open(uri: Uri, flags: Int, persistedOnly: Boolean, callback: (Result<PlatformPdf>) -> Unit) {
        worker.execute {
            val result = runCatching {
                if (!isContentUri(uri.scheme, uri.authority)) throw FlutterError("unreadable")
                persist(uri, flags)
                // A file in a library folder is covered by the folder's grant.
                val target = uri.toString()
                val grants = resolver.persistedUriPermissions
                    .filter { grantCovers(it.uri.toString(), target) }
                val grant = grants.firstOrNull { it.uri == uri } ?: grants.firstOrNull()
                if (persistedOnly && grant?.isReadPermission != true) {
                    throw FlutterError("permissionLost")
                }
                val name = displayName(uri)
                Opened(name, grant?.isReadPermission == true, grant?.isWritePermission == true, source(uri))
            }.recoverCatching { error ->
                throw when (error) {
                    is FlutterError -> error
                    is SecurityException -> FlutterError(if (persistedOnly) "permissionLost" else "unreadable")
                    is FileNotFoundException -> FlutterError("missing")
                    else -> FlutterError("unreadable")
                }
            }
            main.post {
                if (closed) {
                    result.getOrNull()?.source?.closeQuietly()
                    callback(Result.failure(FlutterError("unreadable")))
                } else {
                    callback(result.map { opened ->
                        val id = nextId++
                        leases[id] = opened.source
                        PlatformPdf(id, uri.toString(), opened.name, opened.source.path, opened.read, opened.write)
                    })
                }
            }
        }
    }

    fun release(id: Long) {
        leases.remove(id)?.closeQuietly()
    }

    fun close() {
        closed = true
        leases.values.forEach { it.closeQuietly() }
        leases.clear()
        worker.shutdown()
    }

    private fun persist(uri: Uri, flags: Int) {
        val modes = persistableModes(flags)
        if (modes == 0) return
        try {
            resolver.takePersistableUriPermission(uri, modes)
        } catch (_: SecurityException) {
            // Some providers allow a temporary read but reject persistent write.
            if (modes and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) {
                try {
                    resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: SecurityException) {
                    // The temporary grant can still be used for this open.
                }
            }
        }
    }

    private fun displayName(uri: Uri): String {
        val name = runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        }.getOrNull()
        return name?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment ?: "PDF"
    }

    private fun source(uri: Uri): Source {
        var fd = try {
            resolver.openFileDescriptor(uri, "r")
        } catch (_: FileNotFoundException) {
            // A provider may expose a stream or an asset slice instead.
            null
        }
        try {
            val descriptor = fd
            if (descriptor != null) {
                val path = "/proc/self/fd/${descriptor.fd}"
                if (canReopen(descriptor, path)) {
                    fd = null
                    return Source(path, descriptor)
                }
            }

            val input = if (descriptor == null) {
                resolver.openInputStream(uri) ?: throw FlutterError("unreadable")
            } else {
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).also { fd = null }
            }
            return input.use {
                val file = File.createTempFile(CACHE_PREFIX, ".pdf", context.cacheDir)
                try {
                    file.outputStream().use { output -> input.copyTo(output) }
                    Source(file.absolutePath, Closeable { file.delete() })
                } catch (error: Exception) {
                    file.delete()
                    throw error
                }
            }
        } finally {
            fd?.close()
        }
    }

    private fun canReopen(fd: ParcelFileDescriptor, path: String): Boolean = try {
        Os.lseek(fd.fileDescriptor, 0, OsConstants.SEEK_SET)
        File(path).inputStream().use { }
        true
    } catch (_: ErrnoException) {
        false
    } catch (_: IOException) {
        false
    }

    private data class Opened(val name: String, val read: Boolean, val write: Boolean, val source: Source)

    private data class Source(val path: String, val resource: Closeable) {
        fun closeQuietly() {
            runCatching { resource.close() }
        }
    }
}
