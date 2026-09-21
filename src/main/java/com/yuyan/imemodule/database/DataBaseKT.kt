package com.yuyan.imemodule.database

import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.yuyan.imemodule.application.Launcher
import com.yuyan.imemodule.database.dao.ClipboardDao
import com.yuyan.imemodule.database.dao.PhraseDao
import com.yuyan.imemodule.database.dao.SideSymbolDao
import com.yuyan.imemodule.database.dao.SkbFunDao
import com.yuyan.imemodule.database.dao.UsedSymbolDao
import com.yuyan.imemodule.database.entry.Clipboard
import com.yuyan.imemodule.database.entry.Phrase
import com.yuyan.imemodule.database.entry.SideSymbol
import com.yuyan.imemodule.database.entry.SkbFun
import com.yuyan.imemodule.database.entry.UsedSymbol
import com.yuyan.imemodule.prefs.behavior.SkbMenuMode
import com.yuyan.imemodule.utils.thread.ThreadPoolUtils
import com.yuyan.inputmethod.util.LX17PinYinUtils
import com.yuyan.inputmethod.util.ZX17PinYinUtils

//@Database(entities = [SideSymbol::class, Clipboard::class, UsedSymbol::class], version = 1, exportSchema = false)
@Database(entities = [SideSymbol::class, Clipboard::class, UsedSymbol::class, Phrase::class, SkbFun::class], version = 6, exportSchema = false)
abstract class DataBaseKT : RoomDatabase() {
    abstract fun sideSymbolDao(): SideSymbolDao
    abstract fun clipboardDao(): ClipboardDao
    abstract fun usedSymbolDao(): UsedSymbolDao
    abstract fun phraseDao(): PhraseDao
    abstract fun skbFunDao(): SkbFunDao
    companion object {

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS phrase (content TEXT PRIMARY KEY NOT NULL, isKeep INTEGER NOT NULL, t9 TEXT NOT NULL, qwerty TEXT NOT NULL, lx17 TEXT NOT NULL, time INTEGER NOT NULL)")
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS skbfun (name TEXT KEY NOT NULL, isKeep INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (name, isKeep))")
            }
        }

        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("INSERT INTO skbfun (name, isKeep, position) VALUES ('TextEdit', 0, 15)")
                db.execSQL("INSERT INTO skbfun (name, isKeep, position) VALUES ('TextEdit', 1, 0)")
            }
        }

        private val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // Version 5 used the former name. Version 6 renames it while preserving data.
                db.execSQL("ALTER TABLE phrase ADD COLUMN normal17 TEXT NOT NULL DEFAULT ''")
            }
        }

        private val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // Rebuild instead of ALTER TABLE RENAME COLUMN for Android's older SQLite versions.
                db.execSQL("CREATE TABLE phrase_zx17 (content TEXT NOT NULL, isKeep INTEGER NOT NULL, t9 TEXT NOT NULL, qwerty TEXT NOT NULL, lx17 TEXT NOT NULL, zx17 TEXT NOT NULL DEFAULT '', time INTEGER NOT NULL, PRIMARY KEY(content))")
                db.execSQL("INSERT INTO phrase_zx17 (content, isKeep, t9, qwerty, lx17, zx17, time) SELECT content, isKeep, t9, qwerty, lx17, normal17, time FROM phrase")
                db.execSQL("DROP TABLE phrase")
                db.execSQL("ALTER TABLE phrase_zx17 RENAME TO phrase")
                db.execSQL("UPDATE skbfun SET name = 'PinyinZx17' WHERE name = 'PinyinNormal17'")
            }
        }

        val instance = Room.databaseBuilder(Launcher.instance.context, DataBaseKT::class.java, "ime_db")
            .allowMainThreadQueries()
            .addMigrations(MIGRATION_1_2)
            .addMigrations(MIGRATION_2_3)
            .addMigrations(MIGRATION_3_4)
            .addMigrations(MIGRATION_4_5)
            .addMigrations(MIGRATION_5_6)
            .addCallback(object :Callback(){
                override fun onCreate(db: SupportSQLiteDatabase) {
                    super.onCreate(db)
                    ThreadPoolUtils.executeSingleton {
                        initDb()
                    }
                }

                override fun onOpen(db: SupportSQLiteDatabase) {
                    super.onOpen(db)
                    ThreadPoolUtils.executeSingleton {
                        initPhrasesDb()
                    }
                }
            })
            .build()
        private fun initDb() {  //初始化数据库数据
            val symbolPinyin = listOf("，", "。", "？", "！", "……", "：", "；", ".").map {  symbolKey->
                SideSymbol(symbolKey, symbolKey)
            }
            instance.sideSymbolDao().insertAll(symbolPinyin)
            val symbolNumber = listOf("%", "/", "-", "+", "*", "#", "@").map {  symbolKey->
                SideSymbol(symbolKey, symbolKey, "number")
            }
            instance.sideSymbolDao().insertAll(symbolNumber)
        }

        private fun initPhrasesDb() {  //初始化常用语数据数据
            if(instance.phraseDao().getAll().isEmpty()) {
                val phrases = listOf(
                    Phrase(content = "我的电话是__，常联系。", t9 = "9334", qwerty = "wddh", lx17 = "wddh"),
                    Phrase(content = "抱歉，我现在不方便接电话，稍后联系。", t9 = "2799", qwerty = "bqwx", lx17 = "bqwx"),
                    Phrase(content = "我正在开会，有急事请发短信。", t9 = "9995", qwerty = "wzzk", lx17 = "wwwj"),
                    Phrase(content = "我很快就到，请稍微等一会儿。", t9 = "9455", qwerty = "whkj", lx17 = "whjj"),
                    Phrase(content = "麻烦放驿站，谢谢。", t9 = "6339", qwerty = "mffy", lx17 = "mffy"),
                )
                instance.phraseDao().insertAll(phrases)
            }
            // 由常用语的拼音首字母同时维护两套17键索引，兼容升级前的数据。
            instance.phraseDao().getAll().forEach { phrase ->
                val lx17 = phrase.qwerty.map { LX17PinYinUtils.pinyin2Lx17Key(it) }.joinToString("")
                val zx17 = phrase.qwerty.map { ZX17PinYinUtils.pinyinInitialToKey(it) }.joinToString("")
                if (phrase.lx17 != lx17 || phrase.zx17 != zx17) {
                    instance.phraseDao().update(phrase.copy(lx17 = lx17, zx17 = zx17))
                }
            }
            if(instance.skbFunDao().getAllMenu().isEmpty()) {
                val skbFuns = listOf(
                    SkbFun(name = SkbMenuMode.ClipBoard.name, isKeep = 1),
                    SkbFun(name = SkbMenuMode.Emojicon.name, isKeep = 1),
                    SkbFun(name = SkbMenuMode.TextEdit.name, isKeep = 1),
                    SkbFun(name = SkbMenuMode.Emojicon.name, isKeep = 0, position = 0),
                    SkbFun(name = SkbMenuMode.SwitchKeyboard.name, isKeep = 0, position = 1),
                    SkbFun(name = SkbMenuMode.KeyboardHeight.name, isKeep = 0, position = 2),
                    SkbFun(name = SkbMenuMode.ClipBoard.name, isKeep = 0, position = 3),
                    SkbFun(name = SkbMenuMode.Phrases.name, isKeep = 0, position = 4),
                    SkbFun(name = SkbMenuMode.DarkTheme.name, isKeep = 0, position = 5),
                    SkbFun(name = SkbMenuMode.Feedback.name, isKeep = 0, position = 6),
                    SkbFun(name = SkbMenuMode.OneHanded.name, isKeep = 0, position = 7),
                    SkbFun(name = SkbMenuMode.NumberRow.name, isKeep = 0, position = 8),
                    SkbFun(name = SkbMenuMode.JianFan.name, isKeep = 0, position = 9),
                    SkbFun(name = SkbMenuMode.Mnemonic.name, isKeep = 0, position = 10),
                    SkbFun(name = SkbMenuMode.FloatKeyboard.name, isKeep = 0, position = 11),
                    SkbFun(name = SkbMenuMode.FlowerTypeface.name, isKeep = 0, position = 12),
                    SkbFun(name = SkbMenuMode.Custom.name, isKeep = 0, position = 13),
                    SkbFun(name = SkbMenuMode.Settings.name, isKeep = 0, position = 14),
                    SkbFun(name = SkbMenuMode.TextEdit.name, isKeep = 0, position = 15),
                )
                instance.skbFunDao().insertAll(skbFuns)
            }
        }
    }
}
