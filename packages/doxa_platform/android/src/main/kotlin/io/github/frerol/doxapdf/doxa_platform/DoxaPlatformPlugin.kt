// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
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
    private var folders: LibraryFolders? = null
    private var documentFiles: DocumentFiles? = null
    private var dictionaryImports: DictionaryImports? = null
    private var dictionaryIntents: DictionaryIntentApi? = null
    private val incomingDictionaries = ArrayDeque<Uri>()
    private var pendingDictionary: ((Result<String?>) -> Unit)? = null
    private var pendingFolder: ((Result<PlatformFolder?>) -> Unit)? = null
    private var pdfIntents: PdfIntentApi? = null
    private var pendingPicker: ((Result<PlatformPdf?>) -> Unit)? = null
    private val incoming = ArrayDeque<Intent>()
    private val newIntentListener = NewIntentListener(::queueIntent)
    private val resultListener = ActivityResultListener(::onPickerResult)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        pdfFiles = PdfFiles(flutterPluginBinding.applicationContext)
        folders = LibraryFolders(flutterPluginBinding.applicationContext)
        documentFiles = DocumentFiles(flutterPluginBinding.applicationContext)
        dictionaryImports = DictionaryImports(flutterPluginBinding.applicationContext)
        dictionaryIntents = DictionaryIntentApi(flutterPluginBinding.binaryMessenger)
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

    override fun pickFolder(callback: (Result<PlatformFolder?>) -> Unit) {
        val host = activity
        if (host == null || pendingFolder != null) {
            callback(Result.failure(FlutterError("unreadable")))
            return
        }
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        pendingFolder = callback
        try {
            @Suppress("DEPRECATION")
            host.startActivityForResult(picker, PICK_FOLDER)
        } catch (error: RuntimeException) {
            pendingFolder = null
            callback(Result.failure(FlutterError("unreadable")))
        }
    }

    private fun onFolderResult(resultCode: Int, data: Intent?) {
        val callback = pendingFolder ?: return
        pendingFolder = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            callback(Result.success(null))
            return
        }
        val library = folders
        if (library == null) {
            callback(Result.failure(FlutterError("unreadable")))
            return
        }
        callback(
            runCatching { library.persist(tree, data.flags) }
                .recoverCatching { throw FlutterError("unreadable") },
        )
    }

    override fun listFolder(
        treeUri: String,
        documentId: String?,
        callback: (Result<List<PlatformFolderEntry>>) -> Unit,
    ) {
        val library = folders
        if (library == null) {
            callback(Result.failure(FlutterError("unreadable")))
        } else {
            library.list(treeUri, documentId, callback)
        }
    }

    override fun releaseFolder(treeUri: String) {
        folders?.release(treeUri)
    }

    override fun renameDocument(
        uri: String,
        displayName: String,
        callback: (Result<PlatformMovedDocument>) -> Unit,
    ) {
        documentFiles?.rename(uri, displayName, callback)
            ?: callback(Result.failure(FlutterError("failed")))
    }

    override fun moveDocument(
        uri: String,
        targetTreeUri: String,
        targetDocumentId: String?,
        callback: (Result<PlatformMovedDocument>) -> Unit,
    ) {
        documentFiles?.move(uri, targetTreeUri, targetDocumentId, callback)
            ?: callback(Result.failure(FlutterError("failed")))
    }

    override fun pickDictionaryFiles(callback: (Result<String?>) -> Unit) {
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // StarDict files have no registered mime type.
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            // Downloads is where a pack from the dictionaries page lands.
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildRootUri(DOWNLOADS_AUTHORITY, "downloads"),
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startDictionaryPicker(picker, PICK_DICTIONARY_FILES, callback)
    }

    override fun pickDictionaryFolder(callback: (Result<String?>) -> Unit) {
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startDictionaryPicker(picker, PICK_DICTIONARY_FOLDER, callback)
    }

    private fun startDictionaryPicker(
        picker: Intent,
        requestCode: Int,
        callback: (Result<String?>) -> Unit,
    ) {
        val host = activity
        if (host == null || pendingDictionary != null || dictionaryImports == null) {
            callback(Result.failure(FlutterError("unreadable")))
            return
        }
        pendingDictionary = callback
        try {
            @Suppress("DEPRECATION")
            host.startActivityForResult(picker, requestCode)
        } catch (error: RuntimeException) {
            pendingDictionary = null
            callback(Result.failure(FlutterError("unreadable")))
        }
    }

    private fun onDictionaryResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val callback = pendingDictionary ?: return
        pendingDictionary = null
        val imports = dictionaryImports
        if (resultCode != Activity.RESULT_OK || data == null || imports == null) {
            callback(Result.success(null))
            return
        }
        if (requestCode == PICK_DICTIONARY_FOLDER) {
            val tree = data.data ?: return callback(Result.success(null))
            imports.stageTree(tree, callback)
            return
        }
        val uris = buildList {
            val clips = data.clipData
            if (clips != null) {
                for (i in 0 until clips.itemCount) clips.getItemAt(i).uri?.let(::add)
            } else {
                data.data?.let(::add)
            }
        }
        if (uris.isEmpty()) return callback(Result.success(null))
        imports.stageFiles(uris, callback)
    }

    override fun takeIncomingDictionary(callback: (Result<String?>) -> Unit) {
        val uri = incomingDictionaries.removeFirstOrNull()
        val imports = dictionaryImports
        when {
            uri == null -> callback(Result.success(null))
            imports == null -> callback(Result.failure(FlutterError("unreadable")))
            else -> imports.stageFiles(listOf(uri), callback)
        }
    }

    override fun deleteDocument(uri: String, callback: (Result<Unit>) -> Unit) {
        documentFiles?.delete(uri, callback) ?: callback(Result.failure(FlutterError("failed")))
    }

    private fun onPickerResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == PICK_DICTIONARY_FILES || requestCode == PICK_DICTIONARY_FOLDER) {
            onDictionaryResult(requestCode, resultCode, data)
            return true
        }
        if (requestCode == PICK_FOLDER) {
            onFolderResult(resultCode, data)
            return true
        }
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
        // A dictionary pack opened with "Open with" is imported, not read.
        val data = intent.data
        if (intent.action == Intent.ACTION_VIEW && data != null) {
            val mime = intent.type ?: runCatching { context?.contentResolver?.getType(data) }.getOrNull()
            if (isZipMime(mime)) {
                incomingDictionaries.addLast(data)
                dictionaryIntents?.incomingDictionaryAvailable { }
                return true
            }
        }
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
        pendingFolder?.invoke(Result.success(null))
        pendingFolder = null
        pendingDictionary?.invoke(Result.success(null))
        pendingDictionary = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(binding.binaryMessenger, null)
        pdfIntents = null
        incoming.clear()
        pdfFiles?.close()
        pdfFiles = null
        folders?.close()
        folders = null
        documentFiles?.close()
        documentFiles = null
        dictionaryImports?.close()
        dictionaryImports = null
        dictionaryIntents = null
        incomingDictionaries.clear()
        context = null
    }

    companion object {
        private const val PICK_PDF = 0xD049
        private const val PICK_FOLDER = 0xD04A
        private const val PICK_DICTIONARY_FILES = 0xD04B
        private const val PICK_DICTIONARY_FOLDER = 0xD04C
        private const val DOWNLOADS_AUTHORITY = "com.android.providers.downloads.documents"
        val OPENABLE_SCHEMES = setOf("http", "https", "mailto")
    }
}
