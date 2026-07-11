package be.taxirecettes.copilote

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * LE MOUCHARD (Brique 1) — lecture seule, version filtrée (v0.2).
 *
 * v0.1 dumpait TOUT l'écran à chaque micro-changement (carte qui bouge) → 60 000 lignes
 * en 4 minutes, le journal se remplissait et s'effaçait. v0.2 :
 *  - throttle : au plus 1 lecture d'écran par 1,5 s et par app
 *  - filtre le bruit (repères de carte, chrome de navigation, compteurs qui tournent)
 *  - n'enregistre QUE les écrans de course (offre ou fin) repérés par des mots-clés
 *  - déduplique pour ne pas re-noter la même offre
 * Identifie la plateforme par le CONTENU, pas par le nom de l'app (les offres flottent
 * en overlay par-dessus n'importe quelle app).
 * Packages connus : Uber com.ubercab.driver, Bolt ee.mtakso.driver, Taxis Verts com.godispatch.fr.
 */
class CopiloteAccessibilityService : AccessibilityService() {

    private val lastWalkAt = HashMap<String, Long>()
    private var lastLoggedHash = 0
    private var lastLoggedAt = 0L

    // Mots-repères d'un écran de course (offre ou fin), toutes plateformes confondues.
    private val strongAnchors = listOf(
        "net, ttc", "hors frais", "je suis intéress", "nouvelle demande de course",
        "forte demande", "you get", "le client paie", "destination inconnue",
        "paiement à bord", "collectez", "course terminée", "au comptant", "à percevoir"
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                LogStore.append(this, "${LogStore.ts()} [ECRAN] $pkg / ${event.className}")
                maybeDump(pkg, force = true)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                maybeDump(pkg, force = false)
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                val t = event.text?.joinToString(" ")?.trim() ?: ""
                val l = t.lowercase()
                if (t.isNotBlank() && (l.contains("accepter") || l.contains("refuser") ||
                        l.contains("répondre") || l.contains("intéress"))) {
                    LogStore.append(this, "${LogStore.ts()} [CLIC] $pkg : $t")
                }
            }
        }
    }

    private fun maybeDump(pkg: String, force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force) {
            val last = lastWalkAt[pkg] ?: 0L
            if (now - last < 1500) return
        }
        lastWalkAt[pkg] = now
        try {
            val root = rootInActiveWindow ?: return
            val raw = StringBuilder()
            collect(root, raw, 0, IntArray(1))
            val kept = clean(raw.toString())
            if (kept.isBlank() || !hasRideAnchor(kept)) return
            val h = kept.hashCode()
            if (h == lastLoggedHash && now - lastLoggedAt < 30000) return
            lastLoggedHash = h
            lastLoggedAt = now
            LogStore.append(this, "${LogStore.ts()} [COURSE] $pkg\n$kept")
        } catch (_: Exception) {
        }
    }

    /** Retire le bruit : repères de carte, chrome de navigation, compteurs qui tournent. */
    private fun clean(text: String): String {
        val out = StringBuilder()
        for (raw in text.split("\n")) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val l = line.lowercase()
            if (l.contains("repère sur la carte")) continue
            if (l.contains("carte google")) continue
            if (l.contains("signaler un problème sur la carte")) continue
            if (l.contains("rechercher des lieux")) continue
            // compteurs / minuteries seuls (ex "12", "0:08", "8 s") → volatils, on ignore
            val core = line.trimStart('•', '·', ' ')
            if (core.matches(Regex("^\\d{1,3}$"))) continue
            if (core.matches(Regex("^\\d+\\s*s$"))) continue
            if (core.matches(Regex("^\\d+:\\d+$"))) continue
            out.append(raw).append("\n")
        }
        return out.toString().trim()
    }

    /** L'écran ressemble-t-il à une offre ou une fin de course ? */
    private fun hasRideAnchor(text: String): Boolean {
        val l = text.lowercase()
        for (a in strongAnchors) if (l.contains(a)) return true
        val euro = l.contains("€")
        if (euro && l.contains("refuser") &&
            (l.contains("accepter") || l.contains("répondre") || l.contains("intéress"))
        ) return true
        if (euro && (l.contains("terminé") || l.contains("terminée")) &&
            (l.contains("paiement") || l.contains("comptant") || l.contains("collectez") ||
                l.contains("encaiss") || l.contains("reçu"))
        ) return true
        return false
    }

    private fun collect(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int, count: IntArray) {
        if (node == null) return
        if (depth > 40 || count[0] > 500) return
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
