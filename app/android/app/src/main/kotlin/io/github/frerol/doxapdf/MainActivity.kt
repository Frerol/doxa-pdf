// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ask the system for the app's external files folder so it creates
        // it owned by this app. If `adb push` creates it first, it belongs to
        // the shell user and the app cannot list the developer PDFs in it.
        getExternalFilesDir(null)
    }
}
