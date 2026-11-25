// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import android.content.Intent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class PdfFilesTest {
    @Test
    fun acceptsPdfMimeAndContentUri() {
        assertTrue(isPdfMime("application/pdf"))
        assertTrue(isPdfMime("Application/PDF"))
        assertFalse(isPdfMime("application/octet-stream"))
        assertFalse(isPdfMime(null))
        assertTrue(isContentUri("content", "provider"))
        assertFalse(isContentUri("file", "provider"))
        assertFalse(isContentUri("content", null))
    }

    @Test
    fun persistsOnlyReadAndWriteModesActuallyGranted() {
        val persistable = Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val write = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        assertEquals(0, persistableModes(0))
        assertEquals(0, persistableModes(read or write))
        assertEquals(0, persistableModes(persistable or write))
        assertEquals(read, persistableModes(persistable or read or Intent.FLAG_ACTIVITY_NEW_TASK))
        assertEquals(read or write, persistableModes(persistable or read or write))
    }
}
