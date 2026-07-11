package be.taxirecettes.copilote

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Journal du "mouchard" : on enregistre en clair, sur le téléphone uniquement,
 * ce que l'accessibilité et les notifications voient. Le chauffeur l'exporte
 * lui-même quand il veut. Rotation simple pour ne pas remplir la mémoire.
 */
object LogStore {
    private const val FILE = "mouchard.log"
    private const val MAX_BYTES = 12_000_000L // ~12 Mo (large : le bruit est filtré, une journée entière tient)
    private val lock = Any()
    private val fmt = SimpleDateFormat("dd/MM HH:mm:ss", Locale.FRANCE)

    fun ts(): String = fmt.format(Date())

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences("copilote", Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean("log_enabled", true)

    fun setEnabled(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean("log_enabled", on).apply()
    }

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    fun append(ctx: Context, line: String) {
        if (!isEnabled(ctx)) return
        synchronized(lock) {
            try {
                val f = file(ctx)
                if (f.length() > MAX_BYTES) {
                    val txt = f.readText()
                    f.writeText(txt.substring(txt.length / 2))
                }
                f.appendText(line + "\n")
            } catch (_: Exception) {
            }
        }
    }

    fun read(ctx: Context): String = synchronized(lock) {
        try {
            val f = file(ctx)
            if (f.exists()) f.readText() else ""
        } catch (_: Exception) {
            ""
        }
    }

    fun clear(ctx: Context) = synchronized(lock) {
        try { file(ctx).writeText("") } catch (_: Exception) {}
    }

    fun fileFor(ctx: Context): File = file(ctx)
}
