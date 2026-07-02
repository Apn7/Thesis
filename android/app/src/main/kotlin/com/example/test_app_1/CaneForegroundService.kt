package com.example.test_app_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Foreground service that keeps the Smart Cane link alive while the phone is
 * pocketed with the screen off — the normal way a blind user carries it.
 *
 * Without this, Android freezes the cached app process (and lets the CPU/WiFi
 * doze) minutes after the screen locks, silently killing the TCP frame/sonar
 * servers, YOLO inference, and the obstacle alerts — a fail-silent safety
 * hazard: the user keeps walking, trusting alerts that can no longer fire.
 *
 * The service itself hosts no logic (everything stays in the Dart isolate);
 * it exists to (1) mark the process foreground so it is never frozen, and
 * (2) hold a partial wake lock + WiFi lock so inference and the cane streams
 * keep running with the screen off. Battery cost is the accepted tradeoff for
 * an assistive device in active use; the persistent notification is what
 * tells a sighted helper the cane link is live.
 *
 * Type `connectedDevice` (Android 14+ requirement): the cane IS a connected
 * device — Pi Zero streaming over the phone's own hotspot.
 */
class CaneForegroundService : Service() {

    companion object {
        private const val TAG = "CaneForegroundService"
        private const val CHANNEL_ID = "smart_cane_link"
        private const val NOTIFICATION_ID = 4207

        /** Idempotent: startForegroundService on a running service re-delivers
         *  onStartCommand, which simply re-asserts the same state. */
        fun start(context: Context) {
            context.startForegroundService(
                Intent(context, CaneForegroundService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaneForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        acquireLocks()
        // The Dart isolate owns all real state; a system restart of this
        // service without the Flutter engine would protect nothing.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    /** User swiped the app away: the Flutter engine dies with the task, so a
     *  lingering shield would burn battery guarding a corpse. Stop cleanly. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "SmartCane:fusion",
                ).apply {
                    setReferenceCounted(false)
                    acquire() // held until stop; navigation has no deadline
                }
            } catch (e: Exception) {
                Log.w(TAG, "wake lock unavailable: $e") // degrade, don't die
            }
        }
        if (wifiLock == null) {
            try {
                val wm = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                    "SmartCane:streams",
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            } catch (e: Exception) {
                Log.w(TAG, "wifi lock unavailable: $e")
            }
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "wake lock release failed: $e")
        }
        wakeLock = null
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "wifi lock release failed: $e")
        }
        wifiLock = null
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "স্মার্ট ক্যান সংযোগ / Smart Cane link",
            // LOW: visible in the shade but never makes a sound — the audio
            // channel belongs to the obstacle alerts, not housekeeping.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description =
                "Keeps obstacle detection running while the screen is off"
            setShowBadge(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("স্মার্ট ক্যান সক্রিয় / Smart Cane active")
            .setContentText("বাধা শনাক্তকরণ চলছে / Obstacle detection running")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }
}
