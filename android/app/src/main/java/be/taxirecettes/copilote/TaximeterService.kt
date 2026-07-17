package be.taxirecettes.copilote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import kotlin.math.abs

/**
 * Taximètre natif : tourne en foreground (GPS actif même quand une autre app est
 * au premier plan) et affiche une bulle flottante par-dessus les autres apps.
 * Le calcul vit dans l'objet [Meter] (partagé avec le pont JS).
 */
class TaximeterService : Service() {

    private var wm: WindowManager? = null
    private var bubble: View? = null
    private var bubblePrice: TextView? = null
    private var lm: LocationManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    private val locListener = object : LocationListener {
        override fun onLocationChanged(loc: Location) {
            val t = if (loc.time > 0) loc.time else System.currentTimeMillis()
            Meter.onLocation(loc.latitude, loc.longitude, t, if (loc.hasAccuracy()) loc.accuracy else 0f)
        }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val ticker = object : Runnable {
        override fun run() {
            refresh()
            if (Meter.running) handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundNow()          // exigence Android : passer en foreground tout de suite
        if (!Meter.running) {          // état vide (ex. redémarrage OS) : ne pas lancer un compteur fantôme
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        startLocation()
        showBubble()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
        return START_NOT_STICKY
    }

    private fun startForegroundNow() {
        val notif = buildNotif(Meter.livePrice())
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIF_ID, notif)
            }
        } catch (_: Exception) {
            try { startForeground(NOTIF_ID, notif) } catch (_: Exception) {}
        }
    }

    private fun startLocation() {
        try {
            lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            lm?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, 1000L, 0f, locListener, Looper.getMainLooper()
            )
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "taxi:meter")
            wakeLock?.acquire(4 * 60 * 60 * 1000L)   // garde-fou 4 h max
        } catch (_: Exception) {
        }
    }

    private fun eur(v: Double): String = String.format("%.2f", v).replace('.', ',') + " €"

    private fun refresh() {
        val txt = eur(Meter.livePrice())
        bubblePrice?.text = txt
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotif(Meter.livePrice()))
        } catch (_: Exception) {
        }
    }

    private fun buildNotif(price: Double): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, "Taximètre", NotificationManager.IMPORTANCE_LOW)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setContentTitle("Course en cours — " + eur(price))
            .setContentText("Taximètre actif · touchez pour ouvrir")
            .setSmallIcon(R.drawable.ic_stat_copilote)
            .setOngoing(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showBubble() {
        if (bubble != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) return
        try {
            wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val dp = resources.displayMetrics.density
            val box = LinearLayout(this)
            box.orientation = LinearLayout.VERTICAL
            box.gravity = Gravity.CENTER
            box.setPadding((13 * dp).toInt(), (8 * dp).toInt(), (13 * dp).toInt(), (8 * dp).toInt())
            val bg = GradientDrawable()
            bg.setColor(Color.parseColor("#0B0F16"))
            bg.cornerRadius = 16 * dp
            bg.setStroke((1 * dp).toInt(), Color.parseColor("#40FFB020"))
            box.background = bg

            val tag = TextView(this)
            tag.text = "● TAXI"
            tag.setTextColor(Color.parseColor("#8A5A12"))
            tag.textSize = 9f
            tag.letterSpacing = 0.15f

            val price = TextView(this)
            price.text = eur(Meter.livePrice())
            price.setTextColor(Color.parseColor("#FFB020"))
            price.textSize = 22f
            price.setTypeface(Typeface.MONOSPACE, Typeface.BOLD)

            box.addView(tag)
            box.addView(price)
            bubblePrice = price

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.TOP or Gravity.START
            params.x = (12 * dp).toInt()
            params.y = (130 * dp).toInt()

            box.setOnTouchListener(object : View.OnTouchListener {
                var downX = 0f; var downY = 0f; var initX = 0; var initY = 0; var moved = false
                override fun onTouch(v: View, e: MotionEvent): Boolean {
                    when (e.action) {
                        MotionEvent.ACTION_DOWN -> {
                            downX = e.rawX; downY = e.rawY; initX = params.x; initY = params.y; moved = false
                            return true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val nx = e.rawX - downX; val ny = e.rawY - downY
                            if (abs(nx) > 8 || abs(ny) > 8) moved = true
                            params.x = initX + nx.toInt(); params.y = initY + ny.toInt()
                            try { wm?.updateViewLayout(box, params) } catch (_: Exception) {}
                            return true
                        }
                        MotionEvent.ACTION_UP -> {
                            if (!moved) {
                                try {
                                    startActivity(
                                        Intent(this@TaximeterService, MainActivity::class.java)
                                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                    )
                                } catch (_: Exception) {}
                            }
                            return true
                        }
                    }
                    return false
                }
            })
            wm?.addView(box, params)
            bubble = box
        } catch (_: Exception) {
        }
    }

    private fun teardown() {
        Meter.running = false
        handler.removeCallbacks(ticker)
        try { lm?.removeUpdates(locListener) } catch (_: Exception) {}
        try { if (bubble != null) wm?.removeView(bubble) } catch (_: Exception) {}
        bubble = null; bubblePrice = null
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                stopForeground(STOP_FOREGROUND_REMOVE)
            else
                @Suppress("DEPRECATION") stopForeground(true)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    companion object {
        const val ACTION_STOP = "be.taxirecettes.copilote.STOP_METER"
        private const val CHANNEL = "taxi_meter"
        private const val NOTIF_ID = 42
    }
}
