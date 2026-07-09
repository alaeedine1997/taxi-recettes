package be.taxirecettes.copilote

import android.content.Context
import android.webkit.JavascriptInterface
import org.json.JSONArray

/**
 * Pont entre le carnet (page web) et le natif.
 * La page appelle window.TaxiNative.pullRides() pour aspirer les courses détectées,
 * puis ackRides() pour dire "je les ai enregistrées". Inerte tant qu'aucune course
 * n'est détectée (v0.1).
 */
class TaxiBridge(private val ctx: Context) {

    private val db = MailboxDb(ctx)

    @JavascriptInterface
    fun isNative(): Boolean = true

    @JavascriptInterface
    fun pullRides(): String = try { db.pendingJson() } catch (_: Exception) { "[]" }

    @JavascriptInterface
    fun ackRides(idsJson: String) {
        try {
            val a = JSONArray(idsJson)
            val list = ArrayList<String>(a.length())
            for (i in 0 until a.length()) list.add(a.getString(i))
            db.ack(list)
        } catch (_: Exception) {
        }
    }
}
