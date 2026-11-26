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

internal class LibraryFoldersTest {
    private val tree = "content://com.android.externalstorage.documents/tree/primary%3ABooks"

    @Test
    fun folderGrantCoversOnlyDocumentsInsideItsTree() {
        assertTrue(grantCovers(tree, "$tree/document/primary%3ABooks%2FCalculus.pdf"))
        assertTrue(grantCovers("content://p/doc/1", "content://p/doc/1"))
        // A sibling tree whose name starts the same is a different grant.
        assertFalse(grantCovers(tree, "${tree}2/document/primary%3ABooks2%2Fx.pdf"))
        // A single-document grant does not cover other documents.
        assertFalse(grantCovers("content://p/doc/1", "content://p/doc/1/document/2"))
    }

    @Test
    fun listsFoldersAndPdfsOnly() {
        assertTrue(isListed("vnd.android.document/directory", "Semester 1"))
        assertTrue(isListed("application/pdf", "Calculus"))
        assertTrue(isListed("application/octet-stream", "Notes.PDF"))
        assertFalse(isListed("image/png", "cover.png"))
        assertFalse(isListed(null, "readme.txt"))
    }
}
