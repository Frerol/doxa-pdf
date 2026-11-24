// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.frerol.doxapdf.render_lab

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Creates Android/data/<package>/files so test PDFs can be adb-pushed there.
        getExternalFilesDir(null)
    }
}
