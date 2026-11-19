package com.levelup.levelup_test

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.content.Context
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "levelup_test/control"
    private val prefs by lazy { getSharedPreferences("levelup_gate", Context.MODE_PRIVATE) }
    private val allowedTargets = setOf(
        "com.google.android.youtube",
        "com.instagram.android",
        "com.zhiliaoapp.musically"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> {
                        result.success(mapOf(
                            "target" to prefs.getString("target", "com.google.android.youtube"),
                            "enabled" to prefs.getBoolean("enabled", false),
                            "unlockUntil" to prefs.getLong("unlock_until", 0L),
                            "serviceEnabled" to isServiceEnabled()
                        ))
                    }
                    "setTarget" -> {
                        val target = call.argument<String>("target") ?: ""
                        if (target !in allowedTargets) {
                            result.error("TARGET", "Unsupported test package", null)
                        } else {
                            prefs.edit().putString("target", target).putLong("unlock_until", 0L).apply()
                            LevelUpAccessibilityService.instance?.reevaluate()
                            result.success(true)
                        }
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        prefs.edit().putBoolean("enabled", enabled).apply()
                        LevelUpAccessibilityService.instance?.reevaluate()
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "consumeChallengeRequest" -> {
                        val requested = prefs.getBoolean("open_challenge", false)
                        prefs.edit().putBoolean("open_challenge", false).apply()
                        result.success(requested)
                    }
                    "grantAccess" -> {
                        val minutes = (call.argument<Int>("minutes") ?: 5).coerceIn(1, 15)
                        val unlockUntil = System.currentTimeMillis() + minutes * 60_000L
                        prefs.edit().putLong("unlock_until", unlockUntil).apply()
                        LevelUpAccessibilityService.instance?.reevaluate()
                        result.success(unlockUntil)
                        // Only attempts to return to one of the three user-selected apps.
                        val target = prefs.getString("target", "com.google.android.youtube")
                        if (target in allowedTargets) {
                            val launch = packageManager.getLaunchIntentForPackage(target!!)
                            if (launch != null) {
                                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launch)
                            }
                        }
                    }
                    "resetAccess" -> {
                        prefs.edit().putLong("unlock_until", 0L).apply()
                        LevelUpAccessibilityService.instance?.reevaluate()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isServiceEnabled(): Boolean {
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        ).any { service ->
            service.resolveInfo.serviceInfo.name == LevelUpAccessibilityService::class.java.name
        }
    }
}
