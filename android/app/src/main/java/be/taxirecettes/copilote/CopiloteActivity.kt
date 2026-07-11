package be.taxirecettes.copilote

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat

class CopiloteActivity : AppCompatActivity() {

    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dp = resources.displayMetrics.density
        fun d(v: Int) = (v * dp).toInt()

        val scroll = ScrollView(this)
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.setPadding(d(20), d(24), d(20), d(24))
        scroll.addView(col)

        val title = TextView(this)
        title.text = "Copilote"
        title.textSize = 24f
        col.addView(title)

        status = TextView(this)
        status.textSize = 15f
        status.setPadding(0, d(12), 0, d(18))
        col.addView(status)

        col.addView(makeButton("1. Activer la lecture des courses (accessibilité)") {
            open(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        })
        col.addView(makeButton("2. Autoriser l'accès aux notifications") {
            open(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        })
        col.addView(makeButton("3. Autoriser l'affichage par-dessus les apps") {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (_: Exception) {
                open(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
            }
        })
        col.addView(makeButton("4. Batterie : autoriser en arrière-plan") {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (_: Exception) {
                openAppDetails()
            }
        })
        col.addView(makeButton("5. Démarrage auto (Xiaomi / MIUI)") {
            openMiuiAutostart()
        })

        val sw = Switch(this)
        sw.text = "Enregistrement (mouchard)"
        sw.textSize = 16f
        sw.isChecked = LogStore.isEnabled(this)
        val swlp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        swlp.topMargin = d(18)
        sw.layoutParams = swlp
        sw.setOnCheckedChangeListener { _, on -> LogStore.setEnabled(this, on) }
        col.addView(sw)

        col.addView(makeButton("Voir / partager le journal") {
            startActivity(Intent(this, LogActivity::class.java))
        })

        val note = TextView(this)
        note.text =
            "Le Copilote lit seulement l'écran pour noter tes courses. " +
            "Il n'appuie sur rien et n'accepte aucune course."
        note.textSize = 12f
        note.setPadding(0, d(18), 0, 0)
        col.addView(note)

        setContentView(scroll)
    }

    private fun makeButton(label: String, onClick: () -> Unit): Button {
        val b = Button(this)
        b.text = label
        b.isAllCaps = false
        val lp = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        lp.topMargin = (resources.displayMetrics.density * 8).toInt()
        b.layoutParams = lp
        b.setOnClickListener { onClick() }
        return b
    }

    private fun open(action: String) {
        try {
            startActivity(Intent(action))
        } catch (_: Exception) {
            Toast.makeText(this, "Écran de réglage introuvable", Toast.LENGTH_SHORT).show()
        }
    }

    private fun openAppDetails() {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: Exception) {
        }
    }

    private fun openMiuiAutostart() {
        val candidates = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartDetailManagementActivity"
            )
        )
        for (c in candidates) {
            try {
                val i = Intent()
                i.component = c
                startActivity(i)
                return
            } catch (_: Exception) {
            }
        }
        openAppDetails()
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val acc = if (isAccessibilityOn()) "OK" else "--"
        val notif = if (isNotifOn()) "OK" else "--"
        val overlay = if (Settings.canDrawOverlays(this)) "OK" else "--"
        status.text = "État :\n" +
            "[$acc]  Lecture des courses (accessibilité)\n" +
            "[$notif]  Accès aux notifications\n" +
            "[$overlay]  Affichage par-dessus"
    }

    private fun isAccessibilityOn(): Boolean {
        // Robuste : le système stocke tantôt la forme longue, tantôt la forme courte
        // du composant. On repère simplement notre service par son nom de classe.
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )?.lowercase() ?: return false
        return enabled.contains(packageName.lowercase()) &&
            enabled.contains("copiloteaccessibilityservice")
    }

    private fun isNotifOn(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
}
