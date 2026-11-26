// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import java.io.FileNotFoundException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class DocumentFilesTest {
    @Test
    fun parentIsTheFolderBeforeTheDocumentInItsPath() {
        assertEquals("primary:Books/Sem", parentInPath(listOf("primary:Books", "primary:Books/Sem", "primary:Books/Sem/a.pdf")))
        assertEquals("primary:Books", parentInPath(listOf("primary:Books", "primary:Books/a.pdf")))
        assertNull(parentInPath(listOf("primary:Books")))
    }

    @Test
    fun providerFailuresMapToDartErrorCodes() {
        assertEquals("permissionLost", fileActionError(SecurityException()).code)
        assertEquals("missing", fileActionError(FileNotFoundException()).code)
        assertEquals("unsupported", fileActionError(UnsupportedOperationException()).code)
        assertEquals("failed", fileActionError(IllegalStateException("Failed to rename")).code)
        assertEquals("unsupported", fileActionError(FlutterError("unsupported")).code)
    }
}
