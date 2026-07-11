package be.taxirecettes.copilote

/**
 * Détecteur de course (v1.0-alpha) — analyse le texte d'un écran d'offre et en extrait
 * la plateforme, le montant et le mode de paiement, d'après les vraies structures observées :
 *
 *  Uber        : "UberX  9,22 €  ...  Hors frais de service  ...  Je suis intéressé(e)"
 *  Bolt        : "Bolt  Espèces|Carte  12,42 € (net, TTC)  ...  Refuser / Répondre"
 *  Taxis Verts : "Nouvelle course ... You get €16.81 ... Payer par: Facture | Paiement à bord ... ACCEPTER"
 *
 * IMPORTANT : les montants utilisent un ESPACE INSÉCABLE (U+00A0) avant le € — les regex
 * n'utilisent donc pas \s (qui ne le reconnaît pas) mais des classes tolérantes.
 * Pour l'instant on ne fait qu'IDENTIFIER et journaliser (aucun popup, aucune action).
 */
data class DetectedRide(
    val platform: String,   // Uber | Bolt | Taxis Verts | Privé
    val amount: String,     // normalisé "12,42" (vide si non trouvé)
    val payment: String     // cash | app | ?
) {
    fun key() = "$platform|$amount|$payment"
    fun pretty() = "plateforme=$platform montant=${if (amount.isBlank()) "?" else "$amount €"} paiement=$payment"
}

object RideDetector {

    private val anyFr = Regex("(\\d{1,4},\\d{2})")             // 12,42
    private val anyEn = Regex("(\\d{1,4}\\.\\d{2})")           // 16.81
    private val boltNet = Regex("(\\d{1,4},\\d{2})[^\\d(]{0,8}\\(net")   // 12,42 <nbsp>€ (net
    private val tvYouGet = Regex("you get[^\\d]{0,60}(\\d{1,4}[.,]\\d{2})", RegexOption.IGNORE_CASE)

    fun parse(text: String): DetectedRide? {
        val l = text.lowercase()

        val platform = when {
            l.contains("net, ttc") ||
                (l.contains("bolt") && l.contains("€") &&
                    (l.contains("répondre") || l.contains("refuser"))) -> "Bolt"
            l.contains("hors frais") || l.contains("je suis intéress") ||
                l.contains("uberx") || l.contains("uber x") -> "Uber"
            l.contains("you get") ||
                (l.contains("nouvelle course") && l.contains("payer par")) -> "Taxis Verts"
            else -> return null
        }

        val amount = when (platform) {
            "Bolt" -> boltNet.find(text)?.groupValues?.get(1)
                ?: anyFr.find(text)?.groupValues?.get(1) ?: ""
            "Uber" -> anyFr.find(text)?.groupValues?.get(1) ?: ""
            "Taxis Verts" -> {
                val a = tvYouGet.find(text)?.groupValues?.get(1)
                    ?: anyEn.find(text)?.groupValues?.get(1)
                    ?: anyFr.find(text)?.groupValues?.get(1) ?: ""
                a.replace('.', ',')
            }
            else -> ""
        }

        val payment = when (platform) {
            "Bolt" -> if (l.contains("espèces")) "cash" else "app"   // Carte = payé dans l'app = net
            "Taxis Verts" -> when {
                l.contains("paiement à bord") || l.contains("à bord") -> "cash"
                l.contains("facture") -> "app"
                else -> "?"
            }
            "Uber" -> "?"   // inconnu à l'offre — demandé en fin
            else -> "?"
        }

        return DetectedRide(platform, amount, payment)
    }
}
