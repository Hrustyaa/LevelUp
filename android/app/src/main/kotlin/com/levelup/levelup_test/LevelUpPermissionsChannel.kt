package com.levelup.levelup_test

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Permission UI bridge only: never changes Focus enablement or target. */
internal class LevelUpPermissionsChannel(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
    private val isAccessibilityEnabled: () -> Boolean,
) {
    private val channel = MethodChannel(messenger, "levelup/permissions")
    private val cameraRequestCode = 6321
    private val notificationsRequestCode = 6322
    private var pendingCameraRequest: MethodChannel.Result? = null
    private var pendingNotificationsRequest: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            val permission = call.argument<String>("permission")
            try {
                when (call.method) {
                    "getStates" -> result.success(mapOf(
                        "accessibility" to status(isAccessibilityEnabled()),
                        "camera" to if (activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
                            status(hasCameraPermission()) else "unavailable",
                        "usage" to usageAccessStatus(),
                        "notifications" to notificationsStatus(),
                    ))
                    "openAppSettings" -> open(appSettings(), result)
                    "openPermissionSettings" -> when (permission) {
                        "accessibility" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result)
                        "camera" -> open(appSettings(), result)
                        "usage" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result)
                        "notifications" -> open(notificationSettings(), result)
                        else -> result.error("UNAVAILABLE", "Settings unavailable", null)
                    }
                    "request" -> when (permission) {
                        "accessibility" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result)
                        "camera" -> requestCamera(result)
                        "usage" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result)
                        "notifications" -> requestNotifications(result)
                        else -> result.error("UNAVAILABLE", "Permission unavailable", null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("PERMISSION_ERROR", error.javaClass.simpleName, null)
            }
        }
    }

    private fun status(granted: Boolean) = if (granted) "granted" else "denied"

    private fun hasCameraPermission() =
        activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** Usage access is a special app-op, not a normal runtime permission. */
    private fun usageAccessStatus(): String {
        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return "unknown"
        return try {
            when (appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                activity.packageName,
            )) {
                AppOpsManager.MODE_ALLOWED -> "granted"
                AppOpsManager.MODE_IGNORED, AppOpsManager.MODE_ERRORED,
                AppOpsManager.MODE_DEFAULT -> "denied"
                else -> "unknown"
            }
        } catch (_: SecurityException) {
            "unknown"
        }
    }

    private fun notificationsStatus(): String {
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return "unknown"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) return "denied"
        return status(manager.areNotificationsEnabled())
    }

    private fun appSettings() = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", activity.packageName, null),
    )

    private fun notificationSettings(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            }
        } else appSettings()

    private fun open(intent: Intent, result: MethodChannel.Result) {
        // Some OEM Settings screens are unavailable. Fall back to app details.
        try {
            activity.startActivity(intent)
        } catch (_: android.content.ActivityNotFoundException) {
            activity.startActivity(appSettings())
        }
        result.success(null)
    }

    private fun requestCamera(result: MethodChannel.Result) {
        if (hasCameraPermission()) {
            result.success(null)
            return
        }
        if (pendingCameraRequest != null) {
            result.error("BUSY", "A camera permission request is active", null)
            return
        }
        pendingCameraRequest = result
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), cameraRequestCode)
        } catch (error: Exception) {
            pendingCameraRequest = null
            throw error
        }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (notificationsStatus() == "granted") {
            result.success(null)
            return
        }
        if (pendingNotificationsRequest != null) {
            result.error("BUSY", "A notification permission request is active", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            open(notificationSettings(), result)
            return
        }
        // If the system toggle is disabled but permission is already granted,
        // the user must manage notifications in Android settings.
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) {
            open(notificationSettings(), result)
            return
        }
        pendingNotificationsRequest = result
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationsRequestCode,
            )
        } catch (error: Exception) {
            pendingNotificationsRequest = null
            throw error
        }
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        // Dart re-reads actual Android status after both consent and denial.
        when (requestCode) {
            cameraRequestCode -> {
                val request = pendingCameraRequest
                pendingCameraRequest = null
                request?.success(null)
            }
            notificationsRequestCode -> {
                val request = pendingNotificationsRequest
                pendingNotificationsRequest = null
                request?.success(null)
            }
        }
    }

    fun dispose() {
        pendingCameraRequest?.error("DETACHED", "Activity detached", null)
        pendingCameraRequest = null
        pendingNotificationsRequest?.error("DETACHED", "Activity detached", null)
        pendingNotificationsRequest = null
        channel.setMethodCallHandler(null)
    }
}
