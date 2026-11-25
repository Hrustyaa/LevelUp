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

    private var permissionsBridge: LevelUpPermissionsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        permissionsBridge = LevelUpPermissionsChannel(this, messenger, ::isServiceEnabled)
        AppCatalogChannel.register(applicationContext, messenger, allowedTargets)
        MethodChannel(messenger, channelName)
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
                            LevelUpAccessibilityService.instance?.invalidateChallenge()
                            prefs.edit().putString("target", target).putLong("unlock_until", 0L).apply()
                            LevelUpAccessibilityService.instance?.reevaluate()
                            result.success(true)
                        }
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (!enabled) LevelUpAccessibilityService.instance?.invalidateChallenge()
                        prefs.edit().putBoolean("enabled", enabled).apply()
                        LevelUpAccessibilityService.instance?.reevaluate()
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "setGateLanguage" -> {
                        val language = call.argument<String>("language")
                        if (language in setOf("ru", "en", "kk")) {
                            prefs.edit().putString("language", language).apply()
                        }
                        result.success(null)
                    }
                    "claimFocusChallenge" -> {
                        val request = LevelUpAccessibilityService.instance?.takeIf { isServiceEnabled() }
                        result.success(request?.claimChallenge())
                    }
                    "cancelChallenge" -> {
                        val id = call.argument<String>("id")
                        result.success(id != null &&
                            LevelUpAccessibilityService.instance?.cancelChallenge(id) == true)
                    }
                    "grantAccess" -> {
                        val target = call.argument<String>("target")
                        val service = LevelUpAccessibilityService.instance
                        if (target == null || target !in allowedTargets || !isServiceEnabled() ||
                            service?.consumeCompletedChallenge(
                                call.argument<String>("id"), target, call.argument<Int>("repetitions"),
                            ) != true) {
                            result.error("CHALLENGE", "No matching completed Focus challenge", null)
                        } else {
                            val unlockUntil = System.currentTimeMillis() +
                                LevelUpAccessibilityService.FOCUS_ACCESS_MINUTES * 60_000L
                            prefs.edit().putLong("unlock_until", unlockUntil).apply()
                            service.reevaluate()
                            result.success(unlockUntil)
                            // Preserve the existing automatic launch after a grant.
                            val launch = packageManager.getLaunchIntentForPackage(target)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionsBridge?.onRequestPermissionsResult(requestCode)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        permissionsBridge?.dispose()
        permissionsBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
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
