package be.taxirecettes.copilote

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Boîte aux lettres des courses détectées. Le natif y dépose les courses,
 * la page web (le carnet) vient les récupérer via window.TaxiNative.
 * Pour l'instant (v0.1) elle est vide : c'est la plomberie, prête pour la détection.
 */
class MailboxDb(ctx: Context) : SQLiteOpenHelper(ctx, "mailbox.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE rides(" +
                "id TEXT PRIMARY KEY, ts INTEGER, json TEXT, state TEXT)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldV: Int, newV: Int) {}

    fun pendingJson(): String {
        val out = StringBuilder("[")
        readableDatabase.rawQuery(
            "SELECT json FROM rides WHERE state='pending' ORDER BY ts", null
        ).use { c ->
            var first = true
            while (c.moveToNext()) {
                if (!first) out.append(",")
                out.append(c.getString(0))
                first = false
            }
        }
        out.append("]")
        return out.toString()
    }

    fun ack(ids: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            ids.forEach { db.execSQL("UPDATE rides SET state='done' WHERE id=?", arrayOf(it)) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}
