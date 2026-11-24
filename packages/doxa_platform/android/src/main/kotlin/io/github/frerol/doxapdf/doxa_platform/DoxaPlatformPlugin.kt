// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** DoxaPlatformPlugin */
class DoxaPlatformPlugin :
    FlutterPlugin,
    DoxaPlatformPluginApi {
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(flutterPluginBinding.binaryMessenger, this)
    }

    override fun getPlatformVersion(): String = "Android ${android.os.Build.VERSION.RELEASE}"

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DoxaPlatformPluginApi.setUp(binding.binaryMessenger, null)
    }
}
