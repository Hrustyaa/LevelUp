package com.levelup.levelup_test

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Delivers only confirmed, user-initiated Focus on/off changes.
 * It is not a background service or a reminder scheduler.
 */
internal object LevelUpFocusNotificationsChannel {
    private const val FLUTTER_CHANNEL = "levelup/focus_notifications"
    private const val ANDROID_CHANNEL = "levelup_focus_status_v1"
    private const val NOTIFICATION_ID = 2401

    fun register(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        MethodChannel(messenger, FLUTTER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "postManualChange" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    val language = call.argument<String>("language") ?: "ru"
                    if (enabled == null || language !in setOf("ru", "en", "kk")) {
                        result.error("INVALID_ARGUMENT", "Focus notification arguments are invalid", null)
                        return@setMethodCallHandler
                    }
                    try {
                        postManualChange(appContext, enabled, language)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("NOTIFICATION_ERROR", error.message ?: "Notification failed", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun postManualChange(context: Context, enabled: Boolean, language: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        // Permission to post can be revoked at any time, including in Samsung settings.
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    ANDROID_CHANNEL,
                    "LevelUp Focus",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Notifications when you manually turn Focus on or off"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                }
            )
        }

        val (title, message) = when (language) {
            "en" -> if (enabled) {
                "Focus is on" to "LevelUp is protecting your selected app."
            } else {
                "Focus is off" to "Protection of your selected app is turned off."
            }
            "kk" -> if (enabled) {
                "Фокус қосылды" to "LevelUp таңдалған қолданбаны шектеп тұр."
            } else {
                "Фокус өшірілді" to "Таңдалған қолданбаға шектеу өшірілді."
            }
            else -> if (enabled) {
                "Фокус включён" to "LevelUp ограничивает выбранное приложение."
            } else {
                "Фокус выключен" to "Ограничение выбранного приложения отключено."
            }
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val openApp = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, ANDROID_CHANNEL)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(Notification.CATEGORY_STATUS)
            .build()
        // A stable ID replaces the previous on/off status instead of piling up alerts.
        manager.notify(NOTIFICATION_ID, notification)
    }
}
