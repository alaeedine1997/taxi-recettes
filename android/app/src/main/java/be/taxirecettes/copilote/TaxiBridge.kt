package be.taxirecettes.copilote

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.JavascriptInterface
import androidx.core.content.ContextCompat

/**
 * Pont entre la page web (carnet + taximètre) et le natif.
 * Côté taximètre : la page démarre/arrête le service natif, qui compte au GPS en
 * arrière-plan et affiche la bulle flottante. Le calcul vit dans [Meter].
 */
class TaxiBridge(private val ctx: Context) {

    @JavascriptInterface
    fun isNative(): Boolean = true

    /* ---------------- Taximètre natif (arrière-plan + bulle) ---------------- */

    @JavascriptInterface
    fun hasNativeMeter(): Boolean = true

    @JavascriptInterface
    fun canOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)

    @JavascriptInterface
    fun requestOverlay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(ctx)) {
                val i = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + ctx.packageName)
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(i)
            }
        } catch (_: Exception) {
        }
    }

    @JavascriptInterface
    fun startMeter(tariffs: String): String {
        // Sans permission de localisation, startForeground(...TYPE_LOCATION) lève une
        // SecurityException et Android tue l'app quelques secondes plus tard. On refuse
        // proprement AVANT de lancer le service, et la page affiche le message.
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return "{\"ok\":false,\"err\":\"gps\"}"
        }
        Meter.start(tariffs)
        return try {
            val i = Intent(ctx, TaximeterService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                ctx.startForegroundService(i)
            else
                ctx.startService(i)
            "{\"ok\":true}"
        } catch (_: Exception) {
            "{\"ok\":false,\"err\":\"service\"}"
        }
    }

    @JavascriptInterface
    fun meterState(): String = try { Meter.stateJson() } catch (_: Exception) { "{\"running\":false}" }

    @JavascriptInterface
    fun stopMeter(): String {
        val res = try { Meter.stop() } catch (_: Exception) { "{}" }
        try {
            val i = Intent(ctx, TaximeterService::class.java)
            i.action = TaximeterService.ACTION_STOP
            ctx.startService(i)
        } catch (_: Exception) {
        }
        return res
    }
}
