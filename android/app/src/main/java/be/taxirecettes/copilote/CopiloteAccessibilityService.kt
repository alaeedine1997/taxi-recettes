package be.taxirecettes.copilote

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * LE MOUCHARD + DÉTECTEUR (v0.6) — lecture seule.
 *
 * Corrections apportées après validation sur vraies nuits :
 *  - Chaque plateforme a SA dernière offre (fini les clics Uber/Telegram collés sur Bolt).
 *  - L'acceptation est attribuée à la plateforme du PAQUET qui a émis le clic « Accepter ».
 *  - Uber « Je suis intéressé(e) » = intérêt, PAS gagné ; on confirme via l'écran « Terminer Uber… ».
 *  - Lecture de TOUTES les fenêtres (getWindows) → capte enfin la bulle flottante Uber.
 *  - Déduplication des acceptations (le bouton re-émet ~20 clics).
 * Toujours LOG SEULEMENT (aucun popup, aucune action).
 */
class CopiloteAccessibilityService : AccessibilityService() {

    private var lastWalkAt = 0L
    private var lastLoggedHash = 0
    private var lastLoggedAt = 0L

    private val lastOfferByPlatform = HashMap<String, DetectedRide>()
    private var uberInterested: DetectedRide? = null
    private var lastAcceptKey = ""
    private var lastAcceptAt = 0L

    private val strongAnchors = listOf(
        "net, ttc", "hors frais", "je suis intéress", "nouvelle demande de course",
        "forte demande", "you get", "le client paie", "destination inconnue",
        "paiement à bord", "collectez", "course terminée", "au comptant", "à percevoir", "exclusivité"
    )

    private fun platformOfPackage(pkg: String): String? {
        val p = pkg.lowercase()
        return when {
            p.contains("mtakso") -> "Bolt"
            p.contains("carasap") || p.contains("haulmont") -> "Taxis Verts"
            p.contains("ubercab") -> "Uber"
            else -> null
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                LogStore.append(this, "${LogStore.ts()} [ECRAN] $pkg / ${event.className}")
                scanWindows(force = true)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                scanWindows(force = false)
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                handleClick(pkg, event.text?.joinToString(" ")?.trim() ?: "")
            }
        }
    }

    private fun handleClick(pkg: String, text: String) {
        if (text.isBlank()) return
        val l = text.lowercase()
        val plat = platformOfPackage(pkg)

        if (l.contains("refuser")) {
            if (plat != null) {
                val o = lastOfferByPlatform[plat]
                LogStore.append(this, "${LogStore.ts()} [DÉTECTÉ-REFUSÉE] ${o?.pretty() ?: "plateforme=$plat"}")
                lastOfferByPlatform.remove(plat)
            }
            return
        }

        // Uber Radar : "Je suis intéressé(e)" = intérêt seulement (pas gagné)
        if (l.contains("je suis intéress")) {
            if (plat == "Uber") {
                val o = lastOfferByPlatform["Uber"] ?: RideDetector.parse(text)
                uberInterested = o
                LogStore.append(this, "${LogStore.ts()} [UBER-INTÉRÊT] ${o?.pretty() ?: "?"}")
            }
            return
        }

        // Vraie acceptation : bouton "Accepter" DANS l'app de la plateforme (jamais Telegram/systemui)
        if (l.contains("accepter")) {
            if (plat == null) return
            val offer = lastOfferByPlatform[plat] ?: RideDetector.parse(text)
            if (offer != null && offer.platform == plat) confirmAccept(offer)
        }
    }

    private fun confirmAccept(offer: DetectedRide) {
        val now = System.currentTimeMillis()
        val key = offer.key()
        if (key == lastAcceptKey && now - lastAcceptAt < 90000) return
        lastAcceptKey = key
        lastAcceptAt = now
        LogStore.append(this, "${LogStore.ts()} [DÉTECTÉ-ACCEPTÉE] ${offer.pretty()}")
    }

    /** Parcourt TOUTES les fenêtres (y compris les bulles flottantes Uber). */
    private fun scanWindows(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastWalkAt < 1200) return
        lastWalkAt = now

        val roots = ArrayList<AccessibilityNodeInfo>()
        try { rootInActiveWindow?.let { roots.add(it) } } catch (_: Exception) {}
        try {
            for (w in windows) {
                val r = try { w.root } catch (_: Exception) { null }
                if (r != null && roots.none { it === r }) roots.add(r)
            }
        } catch (_: Exception) {}

        for (root in roots) {
            try {
                val sb = StringBuilder()
                collect(root, sb, 0, IntArray(1))
                val kept = clean(sb.toString())
                if (kept.isBlank()) continue

                // Signal WIN Uber : "Terminer Uber…" pendant une course → confirme l'offre en attente
                if (kept.lowercase().contains("terminer uber") && uberInterested != null) {
                    confirmAccept(uberInterested!!)
                    uberInterested = null
                }

                if (!hasRideAnchor(kept)) continue
                val h = kept.hashCode()
                if (h == lastLoggedHash && now - lastLoggedAt < 30000) continue
                lastLoggedHash = h
                lastLoggedAt = now
                LogStore.append(this, "${LogStore.ts()} [COURSE]\n$kept")

                val ride = RideDetector.parse(kept)
                if (ride != null) {
                    val prev = lastOfferByPlatform[ride.platform]
                    lastOfferByPlatform[ride.platform] = ride
                    if (prev == null || prev.key() != ride.key()) {
                        LogStore.append(this, "${LogStore.ts()} [DÉTECTÉ-OFFRE] ${ride.pretty()}")
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

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
            val core = line.trimStart('•', '·', ' ')
            if (core.matches(Regex("^\\d{1,3}$"))) continue
            if (core.matches(Regex("^\\d+\\s*s$"))) continue
            if (core.matches(Regex("^\\d+:\\d+$"))) continue
            out.append(raw).append("\n")
        }
        return out.toString().trim()
    }

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
