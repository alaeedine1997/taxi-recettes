package be.taxirecettes.copilote

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Envoie la position du chauffeur à Supabase (/positions) PENDANT une course, depuis
 * le service natif — donc même quand l'écran est verrouillé (la page web, elle, gèle
 * son GPS en arrière-plan).
 *
 * Les identifiants (URL, clé publique, jeton, ids) sont fournis par la page web au
 * démarrage du taximètre, UNIQUEMENT si le chauffeur a consenti au partage GPS et a
 * pris une plaque. Tout est best-effort et totalement isolé : une erreur réseau
 * n'affecte JAMAIS le calcul du taximètre.
 *
 * Limite assumée : ne couvre que la durée d'une course (le service natif ne tourne
 * qu'alors) ; entre deux courses, c'est la page web qui envoie (au premier plan).
 */
object PositionPush {

    @Volatile private var url: String? = null
    @Volatile private var key: String? = null
    @Volatile private var token: String? = null
    @Volatile private var driverId: String? = null
    @Volatile private var fleetId: String? = null
    @Volatile private var plateId: String? = null

    @Volatile private var lastSent = 0L
    private const val MIN_INTERVAL = 15000L   // ~15 s, comme la page web
    private const val MAX_ACCURACY = 120f     // on n'envoie pas un fix trop imprécis

    @Synchronized
    fun configure(json: String) {
        try {
            val o = JSONObject(json)
            url = o.optString("url").ifBlank { null }
            key = o.optString("key").ifBlank { null }
            token = o.optString("token").ifBlank { null }
            driverId = o.optString("driverId").ifBlank { null }
            fleetId = o.optString("fleetId").ifBlank { null }
            plateId = o.optString("plateId").ifBlank { null }
            lastSent = 0L
        } catch (_: Exception) { clear() }
    }

    @Synchronized
    fun clear() {
        url = null; key = null; token = null; driverId = null; fleetId = null; plateId = null
    }

    private fun ready(): Boolean =
        url != null && key != null && token != null && driverId != null && fleetId != null

    fun maybePush(lat: Double, lon: Double, accuracy: Float) {
        if (!ready()) return
        if (accuracy > 0f && accuracy > MAX_ACCURACY) return
        val now = System.currentTimeMillis()
        synchronized(this) {
            if (now - lastSent < MIN_INTERVAL) return
            lastSent = now
        }
        val u = url; val k = key; val tok = token; val did = driverId; val fid = fleetId; val pid = plateId
        Thread {
            try {
                val body = JSONArray().put(
                    JSONObject()
                        .put("driver_id", did)
                        .put("fleet_id", fid)
                        .put("plate_id", pid ?: JSONObject.NULL)
                        .put("lat", lat).put("lng", lon)
                        .put("accuracy", Math.round(accuracy).toInt())
                ).toString()
                val conn = (URL("$u/rest/v1/positions").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 8000; readTimeout = 8000
                    doOutput = true
                    setRequestProperty("apikey", k)
                    setRequestProperty("Authorization", "Bearer $tok")
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Prefer", "return=minimal")
                }
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                conn.disconnect()
                // jeton expiré (course > ~1 h) : on arrête d'essayer jusqu'au prochain configure()
                if (code == 401 || code == 403) clear()
            } catch (_: Exception) {
                // hors-ligne / erreur : on réessaiera au prochain point GPS
            }
        }.start()
    }
}
