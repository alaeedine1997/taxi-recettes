package be.taxirecettes.copilote

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

/**
 * Envoie la position du chauffeur à Supabase pendant une course, même lorsque
 * l'écran est verrouillé.
 *
 * Les points sont conservés dans une petite file locale en cas de coupure réseau
 * puis rejoués dans l'ordre. Le jeton utilisateur est renouvelé côté natif : une
 * course longue ou un redémarrage du process ne fige donc plus le traceur.
 */
object PositionPush {
    private const val PREF = "taxi_position_push"
    private const val MIN_INTERVAL = 15_000L
    private const val MAX_ACCURACY = 120f
    private const val MAX_QUEUE = 480       // environ 2 h à un point / 15 s
    private const val BATCH_SIZE = 40

    @Volatile private var url: String? = null
    @Volatile private var key: String? = null
    @Volatile private var token: String? = null
    @Volatile private var refreshToken: String? = null
    @Volatile private var driverId: String? = null
    @Volatile private var fleetId: String? = null
    @Volatile private var plateId: String? = null
    @Volatile private var collecting = false
    @Volatile private var lastSent = 0L
    @Volatile private var uploading = false
    private val refreshLock = Any()

    @Synchronized
    fun configure(ctx: Context, json: String) {
        try {
            val o = JSONObject(json)
            url = o.optString("url").ifBlank { null }
            key = o.optString("key").ifBlank { null }
            token = o.optString("token").ifBlank { null }
            refreshToken = o.optString("refreshToken").ifBlank { null }
            driverId = o.optString("driverId").ifBlank { null }
            fleetId = o.optString("fleetId").ifBlank { null }
            plateId = o.optString("plateId").ifBlank { null }
            collecting = o.optBoolean("collecting", true)
            lastSent = 0L
            persistConfig(ctx)
            launchFlush(ctx)
        } catch (_: Exception) {
            clear(ctx)
        }
    }

    @Synchronized
    fun clear(ctx: Context? = null) {
        collecting = false
        url = null
        key = null
        token = null
        refreshToken = null
        driverId = null
        fleetId = null
        plateId = null
        try {
            ctx?.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                ?.edit()?.remove("config")?.remove("queue")?.apply()
        } catch (_: Exception) {
        }
    }

    /**
     * Arrête de collecter sans effacer la trace hors-ligne. La file est vidée
     * dès que le réseau revient, puis les jetons locaux sont supprimés.
     */
    @Synchronized
    fun stop(ctx: Context) {
        collecting = false
        persistConfig(ctx)
        launchFlush(ctx)
    }

    @Synchronized
    fun restore(ctx: Context) {
        if (ready()) {
            launchFlush(ctx)
            return
        }
        val json = try {
            ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("config", null)
        } catch (_: Exception) {
            null
        }
        if (!json.isNullOrBlank()) configure(ctx, json)
    }

    private fun ready(): Boolean =
        url != null && key != null && token != null && driverId != null && fleetId != null

    fun maybePush(ctx: Context, lat: Double, lon: Double, accuracy: Float, recordedAt: Long) {
        restore(ctx)
        if (!ready() || !collecting || !lat.isFinite() || !lon.isFinite()) return
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return
        if (accuracy > MAX_ACCURACY) return
        val now = System.currentTimeMillis()
        if (recordedAt <= 0L || now - recordedAt > 30_000L || recordedAt - now > 10_000L) return
        synchronized(this) {
            if (now - lastSent < MIN_INTERVAL) return
            lastSent = now
            enqueue(ctx, lat, lon, accuracy, recordedAt)
        }
        launchFlush(ctx)
    }

    @Synchronized
    private fun enqueue(ctx: Context, lat: Double, lon: Double, accuracy: Float, recordedAt: Long) {
        val queue = readQueue(ctx)
        queue.put(
            JSONObject()
                .put("driver_id", driverId)
                .put("fleet_id", fleetId)
                .put("plate_id", plateId ?: JSONObject.NULL)
                .put("lat", lat)
                .put("lng", lon)
                .put("accuracy", Math.round(accuracy).toInt())
                .put("recorded_at", Instant.ofEpochMilli(recordedAt).toString())
        )
        while (queue.length() > MAX_QUEUE) queue.remove(0)
        saveQueue(ctx, queue)
    }

    @Synchronized
    private fun launchFlush(ctx: Context) {
        if (uploading || !ready()) return
        uploading = true
        Thread {
            try {
                flush(ctx.applicationContext)
            } finally {
                synchronized(this) { uploading = false }
            }
        }.start()
    }

    private fun flush(ctx: Context) {
        while (ready()) {
            val batch = peekBatch(ctx)
            if (batch.length() == 0) {
                if (!collecting) clear(ctx)
                return
            }
            val expiredToken = token ?: return
            var code = postBatch(batch, expiredToken)
            if (code == 401) {
                when (refreshAuth(ctx, expiredToken)) {
                    1 -> code = postBatch(batch, token ?: return)
                    -1 -> {
                        clear(ctx)
                        return
                    }
                    else -> return
                }
            }
            when (code) {
                in 200..299 -> dropBatch(ctx, batch.length())
                400, 403 -> {
                    clear(ctx) // session/plaque invalide : ne jamais rejouer ces points plus tard
                    return
                }
                else -> return // hors-ligne/serveur : le prochain fix relancera la file
            }
        }
    }

    private fun postBatch(batch: JSONArray, accessToken: String): Int {
        val u = url ?: return -1
        val k = key ?: return -1
        return try {
            val conn = (URL("$u/rest/v1/positions").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("apikey", k)
                setRequestProperty("Authorization", "Bearer $accessToken")
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Prefer", "return=minimal")
            }
            conn.outputStream.use { it.write(batch.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            try {
                (if (code >= 400) conn.errorStream else conn.inputStream)?.close()
            } catch (_: Exception) {
            }
            conn.disconnect()
            code
        } catch (_: Exception) {
            -1
        }
    }

    /**
     * 1 = renouvelé, 0 = erreur temporaire, -1 = refresh token définitivement refusé.
     */
    private fun refreshAuth(ctx: Context, expiredToken: String): Int = synchronized(refreshLock) {
        if (token != expiredToken && !token.isNullOrBlank()) return@synchronized 1
        val u = url ?: return@synchronized -1
        val k = key ?: return@synchronized -1
        val rt = refreshToken ?: return@synchronized -1
        try {
            val conn = (URL("$u/auth/v1/token?grant_type=refresh_token").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8_000
                readTimeout = 8_000
                doOutput = true
                setRequestProperty("apikey", k)
                setRequestProperty("Content-Type", "application/json")
            }
            val body = JSONObject().put("refresh_token", rt).toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code in 200..299) {
                val data = conn.inputStream.bufferedReader().use { JSONObject(it.readText()) }
                val nextToken = data.optString("access_token")
                val nextRefresh = data.optString("refresh_token")
                conn.disconnect()
                if (nextToken.isBlank()) return@synchronized -1
                token = nextToken
                if (nextRefresh.isNotBlank()) refreshToken = nextRefresh
                persistConfig(ctx)
                return@synchronized 1
            }
            try { conn.errorStream?.close() } catch (_: Exception) {}
            conn.disconnect()
            if (code == 400 || code == 401 || code == 403) -1 else 0
        } catch (_: Exception) {
            0
        }
    }

    @Synchronized
    private fun persistConfig(ctx: Context) {
        val o = JSONObject()
            .put("url", url ?: "")
            .put("key", key ?: "")
            .put("token", token ?: "")
            .put("refreshToken", refreshToken ?: "")
            .put("driverId", driverId ?: "")
            .put("fleetId", fleetId ?: "")
            .put("plateId", plateId ?: "")
            .put("collecting", collecting)
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putString("config", o.toString()).apply()
    }

    @Synchronized
    private fun peekBatch(ctx: Context): JSONArray {
        val queue = readQueue(ctx)
        val batch = JSONArray()
        for (i in 0 until minOf(queue.length(), BATCH_SIZE)) batch.put(queue.getJSONObject(i))
        return batch
    }

    @Synchronized
    private fun dropBatch(ctx: Context, count: Int) {
        val queue = readQueue(ctx)
        repeat(minOf(count, queue.length())) { queue.remove(0) }
        saveQueue(ctx, queue)
    }

    private fun readQueue(ctx: Context): JSONArray = try {
        val raw = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("queue", "[]")
        JSONArray(raw ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    private fun saveQueue(ctx: Context, queue: JSONArray) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putString("queue", queue.toString()).apply()
    }
}
