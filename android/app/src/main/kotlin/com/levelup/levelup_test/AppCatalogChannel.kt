package com.levelup.levelup_test

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream

internal object AppCatalogChannel {
    private const val CHANNEL = "levelup/app_catalog"
    private const val ICON_SIZE = 128
    private val categories = mapOf(
        "com.zhiliaoapp.musically" to "social",
        "com.instagram.android" to "social",
        "com.google.android.youtube" to "entertainment",
    )

    fun register(context: Context, messenger: BinaryMessenger, allowedTargets: Set<String>) {
        val packageManager = context.packageManager
        val supported = categories.filterKeys { it in allowedTargets }
        val worker = messenger.makeBackgroundTaskQueue()
        MethodChannel(messenger, CHANNEL, StandardMethodCodec.INSTANCE, worker)
            .setMethodCallHandler { call, result ->
                if (call.method != "listSupportedApps") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                try {
                    val apps = supported.mapNotNull { (id, category) ->
                        installedApp(packageManager, id, category)
                    }
                    result.success(apps)
                } catch (_: Exception) {
                    result.error("CATALOG_UNAVAILABLE", "Could not load supported apps", null)
                }
            }
    }

    private fun installedApp(
        packageManager: PackageManager,
        id: String,
        category: String,
    ): Map<String, Any>? {
        val info = try {
            @Suppress("DEPRECATION")
            packageManager.getApplicationInfo(id, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            return null
        }
        if (!info.enabled || packageManager.getLaunchIntentForPackage(id) == null) return null

        val label = packageManager.getApplicationLabel(info).toString()
        val icon = try {
            iconPng(packageManager.getApplicationIcon(info))
        } catch (_: RuntimeException) {
            null
        }
        return buildMap {
            put("packageId", id)
            put("name", label)
            put("category", category)
            put("suggested", true)
            if (icon != null) put("icon", icon)
        }
    }

    private fun iconPng(icon: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        val oldBounds = Rect(icon.bounds)
        try {
            icon.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
            icon.draw(Canvas(bitmap))
            return ByteArrayOutputStream().use { bytes ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes))
                bytes.toByteArray()
            }
        } finally {
            icon.bounds = oldBounds
            bitmap.recycle()
        }
    }
}
