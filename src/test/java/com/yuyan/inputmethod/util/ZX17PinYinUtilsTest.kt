package com.yuyan.inputmethod.util

import com.yuyan.inputmethod.data.InputKey
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ZX17PinYinUtilsTest {
    @Test
    fun encodesPinyinWithFlypyAndZX17Groups() {
        assertEquals("BI", ZX17PinYinUtils.pinyin2Key("ni"))
        assertEquals("HC", ZX17PinYinUtils.pinyin2Key("hao"))
        assertEquals("VA", ZX17PinYinUtils.pinyin2Key("zhong"))
        assertEquals("UL", ZX17PinYinUtils.pinyin2Key("shuang"))
        assertEquals("ZT", ZX17PinYinUtils.pinyin2Key("xue"))
        assertEquals("EE", ZX17PinYinUtils.pinyin2Key("er"))
        assertEquals("QI", ZX17PinYinUtils.pinyin2Key("qi"))
        assertEquals("", ZX17PinYinUtils.pinyin2Key("b"))
    }

    @Test
    fun decodesTwoKeyPinyinChoices() {
        val pinyins = ZX17PinYinUtils.zx17KeyToPinyin("BI")
        assertTrue("ni" in pinyins)
    }

    @Test
    fun exposesInitialChoicesForOneKey() {
        assertArrayEquals(
            arrayOf("q", "w"),
            ZX17PinYinUtils.zx17KeyToPinyin("Q"),
        )
    }

    @Test
    fun mapsPhraseInitialsToGroupedKeys() {
        assertEquals("Q", ZX17PinYinUtils.pinyinInitialToKey('w'))
        assertEquals("B", ZX17PinYinUtils.pinyinInitialToKey('n'))
        assertEquals("Z", ZX17PinYinUtils.pinyinInitialToKey('x'))
    }

    @Test
    fun doesNotConfigureSecondExpansionForSelectedFullPinyin() {
        val map = DoublePinYinUtils.doublePinyinMap.getValue("double_pinyin_zx17")
        assertTrue(map.isEmpty())
    }

    @Test
    fun omitsDelimiterWhenSelectedSyllableIsAtInputEnd() {
        val pinyinKey = InputKey.PinyinKey("ni")
        assertEquals("ni", pinyinKey.pinyin(appendDelimiter = false))
        assertEquals("ni'", pinyinKey.pinyin(appendDelimiter = true))
    }
}
