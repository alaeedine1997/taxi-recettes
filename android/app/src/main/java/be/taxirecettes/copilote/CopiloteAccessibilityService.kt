package be.taxirecettes.copilote

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * LE MOUCHARD (Brique 1) — lecture seule.
 * Il n'appuie sur rien, n'accepte aucune course. Il journalise seulement ce qui
 * s'affiche à l'écran des apps de course, pour qu'on calibre la détection sur de vrais écrans.
 */
class CopiloteAccessibilityService : AccessibilityService() {

    // Packages connus des apps de course. Taxis Verts sera découvert via l'heuristique + le journal.
    private val known = setOf("com.ubercab.driver", "ee.mtakso.driver")

    private var lastDumpKey = ""
    private var lastDumpAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // ignore soi-même

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                LogStore.append(this, "${LogStore.ts()} [ECRAN] $pkg / ${event.className}")
                if (interesting(pkg)) dumpTree(pkg, "changement d'écran")
            }

            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                if (interesting(pkg)) dumpTree(pkg, "contenu modifié")
            }

            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val t = event.text?.joinToString(" ")?.trim() ?: ""
                if (t.isNotBlank() && interesting(pkg)) {
                    LogStore.append(this, "${LogStore.ts()} [CLIC] $pkg : $t")
                }
            }
        }
    }

    private fun interesting(pkg: String): Boolean {
        if (pkg in known) return true
        val p = pkg.lowercase()
        return p.contains("taxi") || p.contains("vert") || p.contains("bolt") ||
            p.contains("uber") || p.contains("mtakso") || p.contains("driver") ||
            p.contains("autolux") || p.contains("chauffeur")
    }

    private fun dumpTree(pkg: String, reason: String) {
        // Anti-spam : au plus un dump identique par seconde
        val now = System.currentTimeMillis()
        try {
            val root = rootInActiveWindow ?: return
            val sb = StringBuilder()
            collect(root, sb, 0, intArrayOf(0))
            val body = sb.toString()
            if (body.isBlank()) return
            val key = pkg + "|" + body.hashCode()
            if (key == lastDumpKey && now - lastDumpAt < 1500) return
            lastDumpKey = key
            lastDumpAt = now
            LogStore.append(this, "${LogStore.ts()} [CONTENU] $pkg ($reason)\n$body")
        } catch (_: Exception) {
        }
    }

    private fun collect(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int, count: IntArray) {
        if (node == null) return
        if (depth > 40 || count[0] > 400) return
        count[0]++
        val txt = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        val pad = "  ".repeat(depth.coerceAtMost(12))
        if (!txt.isNullOrBlank()) sb.append(pad).append("• ").append(txt).append("\n")
        else if (!desc.isNullOrBlank()) sb.append(pad).append("· ").append(desc).append("\n")
        val n = node.childCount
        for (i in 0 until n) collect(node.getChild(i), sb, depth + 1, count)
    }

    override fun onInterrupt() {}
}
