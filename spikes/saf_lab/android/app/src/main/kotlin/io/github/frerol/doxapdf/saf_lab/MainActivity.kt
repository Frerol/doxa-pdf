// SPDX-License-Identifier: GPL-3.0-or-later
// Spike C (issue #7): Storage Access Framework read/write-back probe.
package io.github.frerol.doxapdf.saf_lab

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saf_lab").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    pendingPick = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/pdf"
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                        )
                    }
                    startActivityForResult(intent, PICK)
                }
                "copyIn" -> background(result) {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val dest = File(call.argument<String>("path")!!)
                    val t0 = System.nanoTime()
                    contentResolver.openInputStream(uri)!!.use { input -> dest.outputStream().use { input.copyTo(it, 1 shl 20) } }
                    mapOf("ms" to (System.nanoTime() - t0) / 1_000_000, "bytes" to dest.length(), "sha" to sha(dest))
                }
                "writeBack" -> background(result) {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val src = File(call.argument<String>("path")!!)
                    val t0 = System.nanoTime()
                    // "wt": write + truncate. Not every provider honours truncation, so
                    // the result is verified by reading it back.
                    contentResolver.openOutputStream(uri, "wt")!!.use { out -> src.inputStream().use { it.copyTo(out, 1 shl 20) } }
                    val writeMs = (System.nanoTime() - t0) / 1_000_000
                    val check = File(cacheDir, "readback.pdf")
                    contentResolver.openInputStream(uri)!!.use { input -> check.outputStream().use { input.copyTo(it, 1 shl 20) } }
                    val ok = sha(check) == sha(src) && check.length() == src.length()
                    mapOf("ms" to writeMs, "verified" to ok, "bytes" to check.length())
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Spike uses the simple activity-result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        var persisted = true
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            persisted = false
        }
        var name = "?"
        var size = -1L
        var flags = 0
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
                c.getColumnIndex(DocumentsContract.Document.COLUMN_FLAGS).takeIf { it >= 0 }?.let { flags = c.getInt(it) }
            }
        }
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "authority" to (uri.authority ?: "?"),
                "name" to name,
                "size" to size,
                "supportsWrite" to ((flags and DocumentsContract.Document.FLAG_SUPPORTS_WRITE) != 0),
                "persisted" to persisted,
            ),
        )
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("io", "${e.javaClass.simpleName}: ${e.message}", null) }
            }
        }
    }

    private fun sha(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(1 shl 20)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val PICK = 42
    }
}
