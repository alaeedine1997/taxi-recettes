package be.taxirecettes.copilote

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

data class MeterIncrement(
    val accepted: Boolean,
    val distanceM: Double = 0.0,
    val charge: Double = 0.0,
    val tariff: String = "km"
)

object MeterMath {
    const val MAX_PLAUSIBLE_SPEED_KMH = 180.0

    fun increment(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
        seconds: Double,
        ratePerKm: Double,
        ratePerMinute: Double,
        movingThresholdKmh: Double
    ): MeterIncrement {
        if (seconds <= 0.0) return MeterIncrement(accepted = false)
        var distance = haversineMeters(lat1, lon1, lat2, lon2)
        val speedKmh = distance / seconds * 3.6
        if (speedKmh > MAX_PLAUSIBLE_SPEED_KMH) return MeterIncrement(accepted = false)
        if (speedKmh < movingThresholdKmh) distance = 0.0
        val distanceCharge = ratePerKm * (distance / 1000.0)
        val timeCharge = ratePerMinute * (seconds / 60.0)
        return MeterIncrement(
            accepted = true,
            distanceM = distance,
            charge = max(distanceCharge, timeCharge),
            tariff = if (timeCharge > distanceCharge) "temps" else "km"
        )
    }

    fun roundJump(total: Double, jump: Double): Double {
        val safeJump = if (jump > 0.0) jump else 0.10
        return Math.round(Math.round(total / safeJump) * safeJump * 100.0) / 100.0
    }

    fun finalPrice(total: Double, minimum: Double, jump: Double): Double =
        Math.round(max(roundJump(total, jump), minimum) * 100.0) / 100.0

    private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val radius = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * radius * asin(sqrt(a))
    }
}
