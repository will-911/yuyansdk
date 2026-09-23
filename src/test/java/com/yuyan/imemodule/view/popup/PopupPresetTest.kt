package com.yuyan.imemodule.view.popup

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class PopupPresetTest {
    @Test
    fun zx17GroupedKeysExposeIndividualLettersInBothCases() {
        for (label in listOf("QW", "ER", "TY", "OP", "AS", "DF", "JK", "ZX", "BN")) {
            val letters = label.map { it.toString() }
            val expected = (letters + label.lowercase().map { it.toString() }).toTypedArray()
            assertArrayEquals(label, expected, PopupPreset[label])
            assertArrayEquals(label.lowercase(), expected, PopupPreset[label.lowercase()])
        }
    }

    @Test
    fun zx17GroupedKeysKeepTheirLongPressSymbols() {
        for (symbol in listOf("-", "/", "\\", "@", "1", "8", "……", "？")) {
            assertNotNull(symbol, PopupSmallPreset[symbol])
        }
    }
}
