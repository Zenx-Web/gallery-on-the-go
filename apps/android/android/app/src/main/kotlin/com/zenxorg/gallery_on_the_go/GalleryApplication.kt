package com.zenxorg.gallery_on_the_go

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build

class GalleryApplication : Application() {
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()

        // Must exist before flutter_background_service posts its foreground
        // notification on this channel — including on boot-triggered restarts
        // that happen before any Activity or Dart code runs. Creating it here,
        // unconditionally and idempotently, avoids
        // CannotPostForegroundServiceNotificationException.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "gallery_relay_channel",
                "Background Service",
                NotificationManager.IMPORTANCE_LOW,
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        // The background service's own PARTIAL_WAKE_LOCK keeps the CPU
        // running on screen-off, but does nothing for the WiFi radio —
        // Android drops WiFi into power-save mode on lock, which was
        // silently starving the persistent relay socket's keep-alives.
        // Held for the whole process lifetime, mirroring that wake lock.
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        wifiLock = wifiManager?.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "gallery:relay-wifi-lock",
        )?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }
}
