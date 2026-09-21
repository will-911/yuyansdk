package com.yuyan.inputmethod.util

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Normal17PinYinUtilsTest {
    @Test
    fun encodesPinyinWithFlypyAndNormal17Groups() {
        assertEquals("BI", Normal17PinYinUtils.pinyin2Key("ni"))
        assertEquals("HC", Normal17PinYinUtils.pinyin2Key("hao"))
        assertEquals("VA", Normal17PinYinUtils.pinyin2Key("zhong"))
        assertEquals("UL", Normal17PinYinUtils.pinyin2Key("shuang"))
        assertEquals("ZT", Normal17PinYinUtils.pinyin2Key("xue"))
        assertEquals("EE", Normal17PinYinUtils.pinyin2Key("er"))
        assertEquals("QI", Normal17PinYinUtils.pinyin2Key("qi"))
        assertEquals("", Normal17PinYinUtils.pinyin2Key("b"))
    }

    @Test
    fun decodesTwoKeyPinyinChoices() {
        val pinyins = Normal17PinYinUtils.normal17KeyToPinyin("BI")
        assertTrue("ni" in pinyins)
    }

    @Test
    fun exposesInitialChoicesForOneKey() {
        assertArrayEquals(
            arrayOf("q", "w"),
            Normal17PinYinUtils.normal17KeyToPinyin("Q"),
        )
    }

    @Test
    fun mapsPhraseInitialsToGroupedKeys() {
        assertEquals("Q", Normal17PinYinUtils.pinyinInitialToKey('w'))
        assertEquals("B", Normal17PinYinUtils.pinyinInitialToKey('n'))
        assertEquals("Z", Normal17PinYinUtils.pinyinInitialToKey('x'))
    }

    @Test
    fun keepsSelectedFullPinyinInsteadOfExpandingItAgain() {
        assertEquals(
            "ni'",
            DoublePinYinUtils.getDoublePinYinComposition(
                "double_pinyin_normal17",
                "ni'",
                "",
            ),
        )
    }
}
