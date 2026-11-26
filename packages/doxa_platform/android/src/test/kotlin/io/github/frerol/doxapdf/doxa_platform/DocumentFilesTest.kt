// SPDX-License-Identifier: GPL-3.0-or-later

package io.github.frerol.doxapdf.doxa_platform

import java.io.FileNotFoundException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

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

internal class DictionaryImportsTest {
    @Test
    fun zipEntriesNeverLeaveTheStagingFolder() {
        assertEquals("pt/doxa-pt.ifo", safeEntryPath("pt/doxa-pt.ifo"))
        assertEquals("a.dict.dz", safeEntryPath("./a.dict.dz"))
        assertEquals("pt/a.idx", safeEntryPath("pt\\a.idx"))
        for (name in listOf("../a.ifo", "pt/../../a.ifo", "/etc/a.ifo", "C:/a.ifo", "pt/", "__MACOSX/._a.ifo", ".hidden/a.ifo")) {
            assertNull(safeEntryPath(name), name)
        }
    }

    @Test
    fun keepsOnlyDictionaryFilesAndTheirNotes() {
        for (name in listOf("a.ifo", "a.idx", "a.IDX.GZ", "a.dict", "a.dict.dz", "a.syn", "a.syn.dz", "LICENSE.txt", "README")) {
            assertTrue(isDictionaryFile(name), name)
        }
        for (name in listOf("a.exe", "cover.png", "._a.ifo", "a.ifo.bak")) {
            assertFalse(isDictionaryFile(name), name)
        }
    }
}
