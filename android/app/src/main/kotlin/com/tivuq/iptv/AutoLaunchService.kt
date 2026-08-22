package com.tivuq.iptv

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class AutoLaunchService : Service() {
    companion object {
        const val METHOD_CHANNEL = "com.tivuq.iptv/auto_launch"

        private const val NOTIFICATION_CHANNEL_ID = "tivuq_auto_launch"
        private const val NOTIFICATION_ID = 7102
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PREF_ENABLED = "flutter.autoStartOnBoot"

        fun configure(context: Context, enabled: Boolean) {
            val intent = Intent(context, AutoLaunchService::class.java)
            if (!enabled) {
                context.stopService(intent)
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var receiverRegistered = false

    private val wakeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != Intent.ACTION_SCREEN_ON &&
                intent.action != Intent.ACTION_DREAMING_STOPPED
            ) {
                return
            }
            mainHandler.removeCallbacks(launchApp)
            mainHandler.postDelayed(launchApp, 650L)
        }
    }

    private val launchApp = Runnable {
        if (!isEnabled()) {
            stopSelf()
            return@Runnable
        }

        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: return@Runnable
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        runCatching { startActivity(intent) }
    }

    override fun onCreate() {
        super.onCreate()
        if (!isEnabled()) {
            stopSelf()
            return
        }

        startForeground(NOTIFICATION_ID, createNotification())
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_DREAMING_STOPPED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(wakeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(wakeReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isEnabled()) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(launchApp)
        if (receiverRegistered) {
            runCatching { unregisterReceiver(wakeReceiver) }
            receiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun isEnabled(): Boolean = getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE,
    ).getBoolean(PREF_ENABLED, false)

    private fun createNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "TIVUQIPTV otomatik başlatma",
                    NotificationManager.IMPORTANCE_MIN,
                ).apply {
                    description = "TIVUQIPTV'nin Fire TV uyandığında açılmasını sağlar"
                    setShowBadge(false)
                },
            )
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("TIVUQIPTV")
            .setContentText("TV açıldığında otomatik başlatma etkin")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }
}
