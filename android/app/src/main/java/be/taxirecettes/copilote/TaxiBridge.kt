package be.taxirecettes.copilote

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.webkit.JavascriptInterface
import androidx.core.content.ContextCompat
import java.io.File

/**
 * Pont entre la page web (carnet + taximètre) et le natif.
 * Côté taximètre : la page démarre/arrête le service natif, qui compte au GPS en
 * arrière-plan et affiche la bulle flottante. Le calcul vit dans [Meter].
 */
class TaxiBridge(private val ctx: Context) {

    @JavascriptInterface
    fun isNative(): Boolean = true

    /* ---------------- Sauvegarde du carnet dans Téléchargements ----------------
       Le lien blob:// ne télécharge rien dans une WebView : c'est le natif qui
       écrit le fichier, et il renvoie {"ok":true,"path":...} SEULEMENT si l'écriture
       a vraiment réussi (avant, l'app disait « prête » sans rien écrire). */
    @JavascriptInterface
    fun saveBackup(filename: String, content: String): String {
        return try {
            val name = filename.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "taxi-sauvegarde.json" }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = ctx.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "application/json")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return "{\"ok\":false}"
                try {
                    val out = resolver.openOutputStream(uri)
                        ?: run { resolver.delete(uri, null, null); return "{\"ok\":false}" }
                    out.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                    values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                    "{\"ok\":true,\"path\":\"Téléchargements\"}"
                } catch (_: Exception) {
                    resolver.delete(uri, null, null)   // pas d'entrée fantôme "en attente"
                    "{\"ok\":false}"
                }
            } else {
                // Anciennes versions : dossier de l'app (pas de permission requise).
                val dir = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    ?: return "{\"ok\":false}"
                File(dir, name).writeText(content, Charsets.UTF_8)
                "{\"ok\":true,\"path\":\"dossier de l'app / Download / $name\"}"
            }
        } catch (_: Exception) {
            "{\"ok\":false}"
        }
    }

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
        Meter.snapshot(ctx) // immédiat : la course survit même à un kill avant le premier point GPS
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

    /* Partage de position pendant une course : la page fournit les identifiants
       (URL, clé publique, jeton, ids) UNIQUEMENT si consentement + plaque prise. */
    @JavascriptInterface
    fun setPositionAuth(json: String) { try { PositionPush.configure(ctx, json) } catch (_: Exception) {} }

    @JavascriptInterface
    fun clearPositionAuth() { PositionPush.clear(ctx) }

    @JavascriptInterface
    fun stopMeter(): String {
        val res = try { Meter.stop() } catch (_: Exception) { "{}" }
        // Effacer le snapshot ICI (pas seulement via l'intent ACTION_STOP) : si le
        // démarrage du service échouait, un snapshot "running" ressusciterait la course.
        try { Meter.clearSnapshot(ctx) } catch (_: Exception) {}
        try {
            val i = Intent(ctx, TaximeterService::class.java)
            i.action = TaximeterService.ACTION_STOP
            ctx.startService(i)
        } catch (_: Exception) {
        }
        return res
    }
}
