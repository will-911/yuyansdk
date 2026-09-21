package com.yuyan.inputmethod.util

/**
 * 正序 17 键小鹤双拼编码。
 *
 * 键位分组：
 * QW ER TY U I OP
 * AS DF G H JK L
 * ZX C V BN M
 *
 * 每个按键向 Rime 发送该组的代表大写字母。Rime prism 使用相同规则，
 * 先把全拼转换成小鹤双拼，再把 26 个字母压缩成 17 个按键。
 */
object ZX17PinYinUtils {
    private val letterToKey = mapOf(
        'a' to 'A',
        'b' to 'B',
        'c' to 'C',
        'd' to 'D',
        'e' to 'E',
        'f' to 'D',
        'g' to 'G',
        'h' to 'H',
        'i' to 'I',
        'j' to 'J',
        'k' to 'J',
        'l' to 'L',
        'm' to 'M',
        'n' to 'B',
        'o' to 'O',
        'p' to 'O',
        'q' to 'Q',
        'r' to 'E',
        's' to 'A',
        't' to 'T',
        'u' to 'U',
        'v' to 'V',
        'w' to 'Q',
        'x' to 'Z',
        'y' to 'T',
        'z' to 'Z',
    )

    private val finalToFlypyKey = mapOf(
        "iu" to 'q',
        "ei" to 'w',
        "uan" to 'r',
        "ue" to 't',
        "ve" to 't',
        "un" to 'y',
        "uo" to 'o',
        "ie" to 'p',
        "iong" to 's',
        "ong" to 's',
        "ing" to 'k',
        "uai" to 'k',
        "ai" to 'd',
        "en" to 'f',
        "eng" to 'g',
        "iang" to 'l',
        "uang" to 'l',
        "ang" to 'h',
        "ian" to 'm',
        "an" to 'j',
        "ou" to 'z',
        "ia" to 'x',
        "ua" to 'x',
        "iao" to 'n',
        "ao" to 'c',
        "ui" to 'v',
        "in" to 'b',
    )

    private val zeroInitialFlypyCode = mapOf(
        "a" to "aa",
        "ai" to "ad",
        "an" to "aj",
        "ang" to "ah",
        "ao" to "ac",
        "e" to "ee",
        "ei" to "ew",
        "en" to "ef",
        "eng" to "eg",
        "er" to "er",
        "o" to "oo",
        "ou" to "oz",
    )

    private val firstKeyPinyin = mapOf(
        "A" to arrayOf("a", "s"),
        "B" to arrayOf("b", "n"),
        "C" to arrayOf("c"),
        "D" to arrayOf("d", "f"),
        "E" to arrayOf("e", "r"),
        "G" to arrayOf("g"),
        "H" to arrayOf("h"),
        "I" to arrayOf("ch"),
        "J" to arrayOf("j", "k"),
        "L" to arrayOf("l"),
        "M" to arrayOf("m"),
        "O" to arrayOf("o", "p"),
        "Q" to arrayOf("q", "w"),
        "T" to arrayOf("t", "y"),
        "U" to arrayOf("sh"),
        "V" to arrayOf("zh"),
        "Z" to arrayOf("z", "x"),
    )

    private val validPinyins = (LX17PinYinUtils.allPinyinSyllables() + setOf(
        "cei", "dia", "fiao", "kei", "nou", "qi", "rua", "yo", "zhei",
    )) - setOf(
        "b", "c", "ch", "d", "f", "g", "h", "i", "j", "k", "l", "m", "n",
        "p", "q", "r", "s", "sh", "t", "w", "x", "y", "z", "zh",
        "duang", "fuo", "hiu", "ja", "muo",
    )

    private val keyToPinyins: Map<String, Array<String>> = validPinyins
        .mapNotNull { pinyin -> encode(pinyin).takeIf { it.isNotEmpty() }?.let { it to pinyin } }
        .groupBy({ it.first }, { it.second })
        .mapValues { (_, pinyins) -> pinyins.distinct().sorted().toTypedArray() }

    /** 返回当前一键或两键编码可选择的拼音。 */
    fun zx17KeyToPinyin(sequence: String?): Array<String> {
        if (sequence.isNullOrEmpty()) return emptyArray()
        val normalized = sequence.uppercase()
        val prefixChoices = firstKeyPinyin[normalized.take(1)] ?: emptyArray()
        if (normalized.length == 1) return prefixChoices
        val syllableChoices = keyToPinyins[normalized.take(2)] ?: emptyArray()
        return (syllableChoices.asSequence() + prefixChoices.asSequence()).distinct().toList().toTypedArray()
    }

    /** 把完整拼音转换为正序 17 键编码。 */
    fun pinyin2Key(pinyin: String?): String {
        if (pinyin.isNullOrBlank()) return ""
        val normalized = pinyin.lowercase().replace('ü', 'v')
        return if (normalized in validPinyins) encode(normalized) else ""
    }

    internal fun allPinyinSyllables(): Set<String> = validPinyins

    /** 用于常用语首字母索引。 */
    fun pinyinInitialToKey(initial: Char): String =
        letterToKey[initial.lowercaseChar()]?.toString() ?: initial.toString()

    private fun encode(pinyin: String): String {
        val normalized = pinyin.lowercase().replace('ü', 'v')
        val flypyCode = zeroInitialFlypyCode[normalized] ?: run {
            val (initial, final) = splitInitial(normalized)
            if (initial.isEmpty()) return ""
            val initialKey = when (initial) {
                "zh" -> 'v'
                "ch" -> 'i'
                "sh" -> 'u'
                else -> initial[0]
            }
            val finalKey = finalToFlypyKey[final] ?: final.singleOrNull() ?: return ""
            "$initialKey$finalKey"
        }
        return flypyCode.map { letterToKey[it] ?: return "" }.joinToString("")
    }

    private fun splitInitial(pinyin: String): Pair<String, String> {
        val initial = when {
            pinyin.startsWith("zh") -> "zh"
            pinyin.startsWith("ch") -> "ch"
            pinyin.startsWith("sh") -> "sh"
            pinyin.firstOrNull()?.let { it in "bpmfdtnlgkhjqxrzcswy" } == true -> pinyin.take(1)
            else -> ""
        }
        return initial to pinyin.removePrefix(initial)
    }
}
