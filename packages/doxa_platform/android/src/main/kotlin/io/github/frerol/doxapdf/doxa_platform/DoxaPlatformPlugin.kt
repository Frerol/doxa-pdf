// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin

/** DoxaPlatformPlugin */
class DoxaPlatformPlugin :
    FlutterPlugin,
    DoxaPlatformPluginApi {
    private var context: Context? = null

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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(binding.binaryMessenger, null)
        context = null
    }

    companion object {
        val OPENABLE_SCHEMES = setOf("http", "https", "mailto")
    }
}
