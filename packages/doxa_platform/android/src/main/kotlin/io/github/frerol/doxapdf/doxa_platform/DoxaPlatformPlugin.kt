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

/** DoxaPlatformPlugin */
class DoxaPlatformPlugin :
    FlutterPlugin,
    ActivityAware,
    DoxaPlatformPluginApi {
    private var context: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
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

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(binding.binaryMessenger, null)
        context = null
    }

    companion object {
        val OPENABLE_SCHEMES = setOf("http", "https", "mailto")
    }
}
