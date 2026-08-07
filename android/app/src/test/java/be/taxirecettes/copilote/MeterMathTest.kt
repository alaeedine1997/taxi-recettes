package be.taxirecettes.copilote

import java.util.Random
import kotlin.math.max
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeterMathTest {
    @Test
    fun finalPriceMatchesWebOrderForFiftyThousandCases() {
        val random = Random(0x5EEDC0DEL)
        repeat(50_000) {
            val total = Math.round(random.nextDouble() * 500000.0) / 100.0
            val minimum = Math.round(random.nextDouble() * 10000.0) / 100.0
            val jump = max(0.01, Math.round(random.nextDouble() * 100.0) / 100.0)
            val web = Math.round(
                max(Math.round(total / jump) * jump, minimum) * 100.0
            ) / 100.0
            assertEquals(web, MeterMath.finalPrice(total, minimum, jump), 0.0)
        }
    }

    @Test
    fun waitingBillsTimeAndImpossibleJumpIsRejected() {
        val waiting = MeterMath.increment(
            lat1 = 50.8503,
            lon1 = 4.3517,
            lat2 = 50.8503,
            lon2 = 4.3517,
            seconds = 60.0,
            ratePerKm = 2.30,
            ratePerMinute = 0.60,
            movingThresholdKmh = 3.0
        )
        assertTrue(waiting.accepted)
        assertEquals(0.60, waiting.charge, 0.0000001)
        assertEquals("temps", waiting.tariff)

        val impossible = MeterMath.increment(
            lat1 = 50.8503,
            lon1 = 4.3517,
            lat2 = 51.8503,
            lon2 = 4.3517,
            seconds = 1.0,
            ratePerKm = 2.30,
            ratePerMinute = 0.60,
            movingThresholdKmh = 3.0
        )
        assertFalse(impossible.accepted)
    }
}
