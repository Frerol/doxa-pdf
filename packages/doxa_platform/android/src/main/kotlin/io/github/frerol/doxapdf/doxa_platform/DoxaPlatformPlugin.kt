// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

/** DoxaPlatformPlugin */
class DoxaPlatformPlugin :
    FlutterPlugin,
    ActivityAware,
    DoxaPlatformPluginApi {
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity
    private var pdfFiles: PdfFiles? = null
    private var pdfIntents: PdfIntentApi? = null
    private var pendingPicker: ((Result<PlatformPdf?>) -> Unit)? = null
    private val incoming = ArrayDeque<Intent>()
    private val newIntentListener = NewIntentListener(::queueIntent)
    private val resultListener = ActivityResultListener(::onPickerResult)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        pdfFiles = PdfFiles(flutterPluginBinding.applicationContext)
        pdfIntents = PdfIntentApi(flutterPluginBinding.binaryMessenger)
        DoxaPlatformPluginApi.setUp(flutterPluginBinding.binaryMessenger, this)
    }

    override fun getPlatformVersion(): String = "Android ${android.os.Build.VERSION.RELEASE}"

    override fun openUri(uri: String): Boolean {
        // The Dart side already checks the scheme; check again on the host.
        if (uri.substringBefore(':').lowercase() !in OPENABLE_SCHEMES) return false
        val ctx = context ?: return false
        val intent =
            Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            ctx.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    override fun getAccentColor(): Long? {
        val ctx = context ?: return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return ctx.getColor(android.R.color.system_accent1_500).toLong() and 0xFFFFFFFFL
    }

    override fun setKeepScreenOn(keepOn: Boolean) {
        val window = activity?.window ?: return
        if (keepOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun getDataDirectory(): String =
        context?.filesDir?.absolutePath ?: throw IllegalStateException("Not attached")

    override fun pickPdf(callback: (Result<PlatformPdf?>) -> Unit) {
        val host = activity
        if (host == null || pendingPicker != null) {
            callback(Result.failure(FlutterError("unreadable")))
            return
        }
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = PDF_MIME
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        pendingPicker = callback
        try {
            @Suppress("DEPRECATION")
            host.startActivityForResult(picker, PICK_PDF)
        } catch (error: RuntimeException) {
            pendingPicker = null
            callback(Result.failure(FlutterError("unreadable")))
        }
    }

    private fun onPickerResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_PDF) return false
        val callback = pendingPicker ?: return false
        pendingPicker = null
        if (resultCode != Activity.RESULT_OK) {
            callback(Result.success(null))
        } else {
            openPdf(data?.data, data?.flags ?: 0, false, callback)
        }
        return true
    }

    override fun openPersistedPdf(uri: String, callback: (Result<PlatformPdf>) -> Unit) {
        openPdf(Uri.parse(uri), 0, true, callback)
    }

    override fun takeIncomingPdf(callback: (Result<PlatformPdf?>) -> Unit) {
        val intent = incoming.removeFirstOrNull()
        if (intent == null) {
            callback(Result.success(null))
            return
        }
        val uri = try {
            if (intent.action == Intent.ACTION_VIEW) intent.data else sharedUri(intent)
        } catch (_: RuntimeException) {
            null
        }
        // File managers often send VIEW with only the URI; ask the provider.
        val mime = intent.type ?: uri?.let {
            runCatching { context?.contentResolver?.getType(it) }.getOrNull()
        }
        if (uri != null && !isPdfMime(mime)) {
            callback(Result.failure(FlutterError("notPdf")))
            return
        }
        openPdf(uri, intent.flags, false, callback)
    }

    private fun sharedUri(intent: Intent): Uri? {
        @Suppress("DEPRECATION")
        val stream = intent.getParcelableExtra<android.os.Parcelable>(Intent.EXTRA_STREAM)
        return stream as? Uri ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    }

    private fun openPdf(
        uri: Uri?,
        flags: Int,
        persistedOnly: Boolean,
        callback: (Result<PlatformPdf>) -> Unit,
    ) {
        val files = pdfFiles
        when {
            uri == null -> callback(Result.failure(FlutterError("missing")))
            files == null -> callback(Result.failure(FlutterError("unreadable")))
            else -> files.open(uri, flags, persistedOnly, callback)
        }
    }

    override fun releasePdf(leaseId: Long) {
        pdfFiles?.release(leaseId)
    }

    private fun queueIntent(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW && intent.action != Intent.ACTION_SEND) return false
        // Reopening the app from recents redelivers the intent that first
        // launched it; that document must not open again.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return false
        incoming.addLast(intent)
        // Dart also drains on startup, in case its listener is not yet installed.
        pdfIntents?.incomingPdfAvailable { }
        return true
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(resultListener)
        binding.addOnNewIntentListener(newIntentListener)
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(resultListener)
        activityBinding?.removeOnNewIntentListener(newIntentListener)
        activityBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
        binding.activity.intent?.let(::queueIntent)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        attachActivity(binding)

    override fun onDetachedFromActivity() {
        detachActivity()
        pendingPicker?.invoke(Result.success(null))
        pendingPicker = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(binding.binaryMessenger, null)
        pdfIntents = null
        incoming.clear()
        pdfFiles?.close()
        pdfFiles = null
        context = null
    }

    companion object {
        private const val PICK_PDF = 0xD049
        val OPENABLE_SCHEMES = setOf("http", "https", "mailto")
    }
}
