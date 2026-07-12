package com.zenxorg.gallery_on_the_go

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class GalleryApplication : Application() {
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
    }
}
