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
    private val authorization = GateAuthorization()
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
        LevelUpFocusNotificationsChannel.register(applicationContext, messenger)
        permissionsBridge = LevelUpPermissionsChannel(this, messenger, ::isServiceEnabled)
        AppCatalogChannel.register(applicationContext, messenger, allowedTargets)
        LevelUpUsageChannel.register(applicationContext, messenger, allowedTargets)
        MethodChannel(messenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> {
                        val currentMs = System.currentTimeMillis()
                        val target = prefs.getString("target", "com.google.android.youtube") ?: "com.google.android.youtube"
                        val enabled = prefs.getBoolean("enabled", false)
                        val unlockUntil = prefs.getLong("unlock_until", 0L)
                        val remainingMs = if (unlockUntil > currentMs) unlockUntil - currentMs else 0L
                        android.util.Log.d("LevelUpGate", "GET_STATE target=$target enabled=$enabled unlockUntil=$unlockUntil currentMs=$currentMs remainingMs=$remainingMs")
                        result.success(mapOf(
                            "target" to target,
                            "enabled" to enabled,
                            "unlockUntil" to unlockUntil,
                            "serviceEnabled" to isServiceEnabled()
                        ))
                    }
                    "setTarget" -> {
                        val target = call.argument<String>("target") ?: ""
                        if (target !in allowedTargets) {
                            result.error("TARGET", "Unsupported test package", null)
                        } else {
                            if (target != currentTarget()) {
                                authorization.clear()
                                prefs.edit().putString("target", target)
                                    .remove("open_challenge_target")
                                    .putLong("unlock_until", 0L).apply()
                                LevelUpAccessibilityService.instance?.reevaluate()
                            }
                            result.success(true)
                        }
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val editor = prefs.edit().putBoolean("enabled", enabled)
                        if (!enabled) {
                            authorization.clear()
                            editor.remove("open_challenge_target")
                        }
                        editor.apply()
                        LevelUpAccessibilityService.instance?.reevaluate()
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = android.net.Uri.fromParts("package", packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "checkCameraPermission" -> {
                        val granted = checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        result.success(if (granted) "granted" else "denied")
                    }
                    "consumeChallengeRequest" -> {
                        val requestedTarget = prefs.getString("open_challenge_target", null)
                        prefs.edit().remove("open_challenge_target").apply()
                        val target = currentTarget()
                        result.success(
                            authorization.claim(requestedTarget, target, isEligible(target))
                        )
                    }
                    "grantAccess" -> {
                        val target = currentTarget()
                        val startMs = System.currentTimeMillis()
                        val previousExpiry = prefs.getLong("unlock_until", 0L)
                        val unlockUntil = authorization.takeGrant(
                            expectedTarget = call.argument<String>("target"),
                            currentTarget = target,
                            eligible = isEligible(target),
                            minutes = call.argument<Int>("minutes"),
                            nowMs = startMs,
                            unlockUntilMs = previousExpiry,
                        )
                        if (unlockUntil == null) {
                            result.error("GATE_DENIED", "No eligible Gate claim", null)
                        } else if (!prefs.edit().putLong("unlock_until", unlockUntil).commit()) {
                            prefs.edit().putLong("unlock_until", previousExpiry).apply()
                            result.error("GRANT_PERSIST_FAILED", "Could not store access", null)
                        } else {
                            LevelUpAccessibilityService.instance?.reevaluate()
                            result.success(unlockUntil)
                            try {
                                packageManager.getLaunchIntentForPackage(target)?.let { launch ->
                                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(launch)
                                }
                            } catch (e: Exception) {
                                android.util.Log.w("LevelUpGate", "Access granted; could not reopen target", e)
                            }
                        }
                    }
                    "resetAccess" -> {
                        authorization.clear()
                        prefs.edit().remove("open_challenge_target")
                            .putLong("unlock_until", 0L).apply()
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

    private fun currentTarget(): String =
        prefs.getString("target", "com.google.android.youtube") ?: "com.google.android.youtube"

    private fun isEligible(target: String): Boolean =
        target in allowedTargets && prefs.getBoolean("enabled", false) && isServiceEnabled()

    private fun isServiceEnabled(): Boolean {
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        ).any { service ->
            service.resolveInfo.serviceInfo.name == LevelUpAccessibilityService::class.java.name
        }
    }
}
