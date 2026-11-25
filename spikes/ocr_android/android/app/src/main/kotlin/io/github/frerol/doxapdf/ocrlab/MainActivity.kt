// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.frerol.doxapdf.ocrlab

import android.app.Activity
import android.content.Intent
import android.system.Os
import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val stopLock = Any()
    private var pendingPick: MethodChannel.Result? = null
    private var tess: TessBaseAPI? = null // Owned by worker.
    private var recognizing: TessBaseAPI? = null // Protected by stopLock.
    @Volatile private var cancelled = false
    private var cancelTime = 0L
    private val models = mapOf(
        "por" to "c4932b937207a9514b7514d518b931a99938c02a28a5a5a553f8599ed58b7deb",
        "eng" to "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
    )

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "ocr_lab").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    pendingPick = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/pdf"
                    }, PICK)
                }
                "init" -> {
                    synchronized(stopLock) {
                        cancelled = false
                        cancelTime = 0
                    }
                    background(result) { initialize() }
                }
                "recognize" -> background(result) {
                    recognize(
                        requireNotNull(call.argument<ByteArray>("pixels")),
                        requireNotNull(call.argument<Int>("width")),
                        requireNotNull(call.argument<Int>("height")),
                    )
                }
                "cancel" -> {
                    requestStop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestStop() = synchronized(stopLock) {
        cancelled = true
        cancelTime = System.nanoTime()
        recognizing?.stop()
    }

    @Deprecated("Uses the activity-result API for the SAF picker")
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
        background(result) {
            val session = java.nio.file.Files.createTempDirectory(cacheDir.toPath(), "ocr-").toFile()
            val source = File(session, "source.pdf")
            try {
                requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                    source.outputStream().use { input.copyTo(it) }
                }
                source.absolutePath
            } catch (error: Exception) {
                session.deleteRecursively()
                throw error
            }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread { result.error("ocr_lab", error.toString(), null) }
            } catch (error: LinkageError) {
                runOnUiThread { result.error("ocr_lab", error.toString(), null) }
            }
        }
    }

    private fun initialize(): Double {
        if (tess != null) return 0.0
        val root = File(filesDir, "tesseract")
        val data = File(root, "tessdata").apply { mkdirs() }
        for ((language, digest) in models) {
            check(!cancelled) { "Cancelled" }
            ensureModel(data, language, digest)
        }

        val start = System.nanoTime()
        // The progress callback also covers a stop arriving just before native
        // recognition starts and resets its stop flag.
        val api = TessBaseAPI { if (cancelled) synchronized(stopLock) { recognizing?.stop() } }
        try {
            check(api.init(root.absolutePath, "por+eng", TessBaseAPI.OEM_LSTM_ONLY))
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            tess = api
        } finally {
            if (tess == null) api.recycle()
        }
        return elapsedMs(start)
    }

    private fun ensureModel(data: File, language: String, expected: String) {
        val target = File(data, "$language.traineddata")
        if (target.isFile && sha256(target) == expected) return
        val start = System.nanoTime()
        val pending = File.createTempFile(language, ".download", data)
        try {
            val url = URL("https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/${target.name}")
            val connection = url.openConnection() as HttpsURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                check(connection.responseCode == 200) { "HTTP ${connection.responseCode} for $language" }
                connection.inputStream.use { input ->
                    pending.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        var bytes = 0L
                        while (true) {
                            check(!cancelled) { "Cancelled" }
                            val count = input.read(buffer)
                            if (count < 0) break
                            bytes += count
                            check(bytes <= 4_200_000) { "Oversized language model" }
                            output.write(buffer, 0, count)
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }
            val actual = sha256(pending)
            check(actual == expected) { "SHA-256 mismatch for $language" }
            check(!cancelled) { "Cancelled" }
            Os.rename(pending.absolutePath, target.absolutePath)
            Log.i("OCRLAB", "model=$language bytes=${target.length()} sha256=$actual download_ms=${elapsedMs(start)}")
        } finally {
            pending.delete()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun recognize(gray: ByteArray, width: Int, height: Int): Map<String, Any> {
        val api = checkNotNull(tess)
        val start = System.nanoTime()
        check(!cancelled) { "Cancelled" }
        try {
            api.setImage(gray, width, height, 1, width)
            synchronized(stopLock) {
                check(!cancelled) { "Cancelled" }
                recognizing = api
            }
            try {
                // This is the interruptible recognition entry point in 4.9.0.
                api.getHOCRText(0)
            } finally {
                synchronized(stopLock) {
                    recognizing = null
                    if (cancelTime != 0L) {
                        Log.i("OCRLAB", "native_stop_ms=${elapsedMs(cancelTime)}")
                    }
                }
            }
            check(!cancelled) { "Cancelled" }
            val words = mutableListOf<Map<String, Any>>()
            api.resultIterator?.let { iterator ->
                try {
                    val level = TessBaseAPI.PageIteratorLevel.RIL_WORD
                    iterator.begin()
                    do {
                        check(!cancelled) { "Cancelled" }
                        val text = iterator.getUTF8Text(level)?.trim().orEmpty()
                        val box = iterator.getBoundingRect(level)
                        if (text.isNotEmpty() && box != null && !box.isEmpty) {
                            words.add(mapOf("text" to text, "confidence" to iterator.confidence(level),
                                "left" to box.left, "top" to box.top, "right" to box.right, "bottom" to box.bottom))
                        }
                    } while (iterator.next(level))
                } finally {
                    iterator.delete()
                }
            }
            return mapOf("words" to words, "ocr_ms" to elapsedMs(start))
        } finally {
            api.clear()
        }
    }

    override fun onDestroy() {
        requestStop()
        worker.execute { tess?.recycle() }
        worker.shutdown()
        super.onDestroy()
    }

    private fun elapsedMs(start: Long) = (System.nanoTime() - start) / 1_000_000.0

    private companion object {
        const val PICK = 42
    }
}
