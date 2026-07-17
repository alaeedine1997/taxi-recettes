package be.taxirecettes.copilote

import org.json.JSONObject
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Cœur du taximètre. C'est un singleton partagé entre le service natif (GPS en
 * arrière-plan) et le pont JS (TaxiBridge) — même process, donc état cohérent.
 *
 * Algo identique à la version web :
 *   total = prise en charge, puis à chaque point GPS on ajoute
 *   max(tarifKm * dkm, tarifMinute * dmin)  (bascule : km en roulant, attente à l'arrêt)
 *   Le minimum de course n'est appliqué QU'À L'ARRÊT.
 */
object Meter {

    @Volatile var running = false

    // tarifs (repli sur les valeurs Bruxelles si absent)
    private var priseEnCharge = 2.60
    private var tarifKm = 2.30
    private var tarifMinute = 0.60
    private var minimumCourse = 8.00
    private var saut = 0.10
    private var vitesseMinRoule = 3.0
    private var precisionMax = 25.0

    // état de la course
    @Volatile private var total = 0.0
    @Volatile private var distanceM = 0.0
    @Volatile private var startAt = 0L
    @Volatile private var tarifNow = "km"
    private var lastLat = 0.0
    private var lastLon = 0.0
    private var lastT = 0L
    private var hasLast = false

    @Volatile var lastResult = "{}"

    fun start(tariffs: String) {
        try {
            val o = JSONObject(tariffs)
            priseEnCharge = o.optDouble("priseEnCharge", 2.60)
            tarifKm = o.optDouble("tarifKm", 2.30)
            tarifMinute = o.optDouble("tarifMinute", 0.60)
            minimumCourse = o.optDouble("minimumCourse", 8.00)
            val s = o.optDouble("sautCompteur", 0.10)
            saut = if (s > 0) s else 0.10
            vitesseMinRoule = o.optDouble("vitesseMinRoule", 3.0)
            precisionMax = o.optDouble("precisionMax", 25.0)
        } catch (_: Exception) {
        }
        total = priseEnCharge
        distanceM = 0.0
        tarifNow = "km"
        hasLast = false
        startAt = System.currentTimeMillis()
        running = true
    }

    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }

    @Synchronized
    fun onLocation(lat: Double, lon: Double, t: Long, accuracy: Float) {
        if (!running) return
        if (accuracy > 0f && accuracy > precisionMax) return   // point trop imprécis
        if (hasLast) {
            val dt = (t - lastT) / 1000.0
            if (dt > 0) {
                var dd = haversine(lastLat, lastLon, lat, lon)
                if ((dd / dt) * 3.6 < vitesseMinRoule) dd = 0.0   // à l'arrêt : anti-dérive GPS
                distanceM += dd
                val compKm = tarifKm * (dd / 1000.0)
                val compMin = tarifMinute * (dt / 60.0)
                total += max(compKm, compMin)
                tarifNow = if (compMin > compKm) "temps" else "km"
            }
        }
        lastLat = lat; lastLon = lon; lastT = t; hasLast = true
    }

    private fun roundSaut(p: Double): Double = Math.round(p / saut) * saut

    fun livePrice(): Double = roundSaut(total)
    private fun finalPrice(): Double = roundSaut(max(total, minimumCourse))
    fun km(): Double = Math.round(distanceM / 10.0) / 100.0
    fun seconds(): Long = if (startAt == 0L) 0 else (System.currentTimeMillis() - startAt) / 1000

    fun stateJson(): String = JSONObject().apply {
        put("running", running)
        put("price", livePrice())
        put("km", km())
        put("seconds", seconds())
        put("tarif", tarifNow)
    }.toString()

    @Synchronized
    fun stop(): String {
        lastResult = JSONObject().apply {
            put("price", finalPrice())
            put("km", km())
            put("seconds", seconds())
            put("minApplied", total < minimumCourse)
        }.toString()
        running = false
        return lastResult
    }
}
