// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract.Document
import android.system.ErrnoException
import android.system.OsConstants
import java.io.File
import java.io.InputStream
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Serializes document writes and verification on a worker. */
internal class PdfSaves(private val context: Context) {
    private val resolver = context.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun canWrite(uri: String, callback: (Result<Boolean>) -> Unit) = perform(callback) {
        try {
            writeRestriction(contentUri(uri)) == null
        } catch (_: SecurityException) {
            false
        }
    }

    fun writeBack(uri: String, tempPath: String, callback: (Result<Unit>) -> Unit) = perform(callback) {
        val target = contentUri(uri)
        writeRestriction(target)?.let { throw FlutterError(it) }

        File(tempPath).inputStream().use { source ->
            val backup = File.createTempFile("saf-recovery-", ".pdf", context.cacheDir)
            try {
                openInput(target).use { input ->
                    backup.outputStream().use { input.copyTo(it) }
                }
            } catch (error: Exception) {
                backup.delete()
                throw error
            }

            try {
                writeAndVerify(target, source)
            } catch (error: Exception) {
                throw FlutterError(
                    saveError(error).code,
                    details = mapOf("recoveryPath" to backup.absolutePath),
                )
            }
            backup.delete()
            Unit
        }
    }

    fun saveCopy(uri: Uri, tempPath: String, callback: (Result<String?>) -> Unit) = perform(callback) {
        val target = contentUri(uri.toString())
        File(tempPath).inputStream().use { writeAndVerify(target, it) }
        target.toString()
    }

    fun close() {
        worker.shutdown()
    }

    private fun writeRestriction(uri: Uri): String? {
        if (resolver.persistedUriPermissions.none {
                it.isWritePermission && grantCovers(it.uri.toString(), uri.toString())
            }
        ) return "permissionLost"

        val flags = resolver.query(uri, arrayOf(Document.COLUMN_FLAGS), null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(Document.COLUMN_FLAGS)
            if (cursor.moveToFirst() && column >= 0) cursor.getInt(column) else null
        } ?: return "readOnly"
        return if (flags and Document.FLAG_SUPPORTS_WRITE != 0) null else "readOnly"
    }

    private fun writeAndVerify(uri: Uri, source: InputStream) {
        val expected = MessageDigest.getInstance("SHA-256")
        // Only success after closing the output and independently reading back
        // the bytes. A provider may ignore the truncate flag or buffer writes.
        val output = resolver.openOutputStream(uri, "wt") ?: throw FlutterError("failed")
        output.use { DigestInputStream(source, expected).copyTo(it) }
        val actual = MessageDigest.getInstance("SHA-256")
        openInput(uri).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count == -1) break
                actual.update(buffer, 0, count)
            }
        }
        if (!expected.digest().contentEquals(actual.digest())) throw FlutterError("mismatch")
    }

    private fun openInput(uri: Uri): InputStream =
        resolver.openInputStream(uri) ?: throw FlutterError("failed")

    private fun <T> perform(callback: (Result<T>) -> Unit, action: () -> T) {
        worker.execute {
            val result = runCatching(action).recoverCatching { throw saveError(it) }
            main.post { callback(result) }
        }
    }
}

internal fun contentUri(value: String): Uri = Uri.parse(value).also {
    if (it.scheme != "content" || it.authority.isNullOrEmpty()) throw FlutterError("failed")
}

internal fun saveError(error: Throwable): FlutterError {
    if (error is FlutterError) return error
    for (cause in generateSequence(error) { it.cause }) {
        if (cause is SecurityException) return FlutterError("permissionLost")
        // Binder/provider I/O may retain the errno only in the exception message.
        val errno = (cause as? ErrnoException)?.errno
        val message = cause.message.orEmpty()
        if (errno == OsConstants.ENOSPC || errno == OsConstants.EDQUOT ||
            "ENOSPC" in message || "EDQUOT" in message
        ) return FlutterError("noSpace")
        if (errno == OsConstants.EROFS || "EROFS" in message) return FlutterError("readOnly")
    }
    return FlutterError("failed")
}
