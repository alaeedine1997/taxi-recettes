package be.taxirecettes.copilote

/**
 * Détecteur de course (v1.0-alpha) — analyse le texte d'un écran d'offre et en extrait
 * la plateforme, le montant et le mode de paiement, d'après les vraies structures observées :
 *
 *  Uber        : "UberX  9,22 €  ...  Hors frais de service  ...  Je suis intéressé(e)"
 *  Bolt        : "Bolt  Espèces  15,16 € (net, TTC)  ...  Refuser / Répondre"
 *  Taxis Verts : "Nouvelle course ... You get €16.81 ... Payer par: Facture / Paiement à bord ... ACCEPTER"
 *
 * Pour l'instant on ne fait qu'IDENTIFIER et journaliser (aucun popup, aucune action).
 */
data class DetectedRide(
    val platform: String,   // Uber | Bolt | Taxis Verts | Privé
    val amount: String,     // normalisé "15,16" (vide si non trouvé)
    val payment: String     // cash | app | ?
) {
    fun key() = "$platform|$amount|$payment"
    fun pretty() = "plateforme=$platform montant=${if (amount.isBlank()) "?" else "$amount €"} paiement=$payment"
}

object RideDetector {

    private val reFr = Regex("(\\d{1,4},\\d{2})")            // 15,16
    private val reEn = Regex("(\\d{1,4}\\.\\d{2})")          // 16.81

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
            "Bolt" -> {
                // montant "net, TTC" en priorité
                val m = Regex("(\\d{1,4},\\d{2})\\s*€\\s*\\(net").find(text)
                    ?: reFr.find(text)?.let { Regex("(\\d{1,4},\\d{2})\\s*€").find(text) }
                (m?.groupValues?.get(1)) ?: (reFr.find(text)?.value ?: "")
            }
            "Uber" -> {
                // premier montant en euros de l'offre
                Regex("(\\d{1,4},\\d{2})\\s*€").find(text)?.groupValues?.get(1)
                    ?: (reFr.find(text)?.value ?: "")
            }
            "Taxis Verts" -> {
                // "You get €16.81" (format point) ; on renormalise en virgule
                val en = Regex("you get[^\\d]{0,20}€?\\s*(\\d{1,4}[.,]\\d{2})", RegexOption.IGNORE_CASE).find(text)
                    ?.groupValues?.get(1)
                    ?: Regex("€\\s*(\\d{1,4}[.,]\\d{2})").find(text)?.groupValues?.get(1)
                    ?: (reEn.find(text)?.value ?: reFr.find(text)?.value ?: "")
                en.replace('.', ',')
            }
            else -> ""
        }

        val payment = when (platform) {
            "Bolt" -> if (l.contains("espèces")) "cash" else "app"
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
