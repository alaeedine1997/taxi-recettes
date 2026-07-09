package be.taxirecettes.copilote

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Canal de secours : les notifications de gains Uber/Bolt changent moins souvent que les écrans.
 * Lecture seule, journalisation uniquement.
 */
class CopiloteNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return
        val p = pkg.lowercase()
        val ok = p.contains("taxi") || p.contains("vert") || p.contains("bolt") ||
            p.contains("uber") || p.contains("mtakso") || p.contains("driver") ||
            p.contains("autolux") || p.contains("chauffeur")
        if (!ok) return
        val ex = sbn.notification?.extras ?: return
        val title = ex.getCharSequence("android.title")?.toString()?.trim() ?: ""
        val text = ex.getCharSequence("android.text")?.toString()?.trim() ?: ""
        val big = ex.getCharSequence("android.bigText")?.toString()?.trim() ?: ""
        val body = if (big.isNotBlank()) big else text
        if (title.isBlank() && body.isBlank()) return
        LogStore.append(this, "${LogStore.ts()} [NOTIF] $pkg : $title — $body")
    }
}
