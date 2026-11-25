package com.levelup.levelup_test

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Bridges the existing permissions UI to Android without changing Focus state. */
internal class LevelUpPermissionsChannel(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
    private val isAccessibilityEnabled: () -> Boolean,
) {
    private val channel = MethodChannel(messenger, "levelup/permissions")
    private val cameraRequestCode = 6321
    private var pendingCameraRequest: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            val permission = call.argument<String>("permission")
            try {
                when (call.method) {
                    "getStates" -> result.success(mapOf(
                        "accessibility" to status(isAccessibilityEnabled()),
                        "camera" to if (activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
                            status(hasCameraPermission()) else "unavailable",
                        "usage" to "unknown",
                        "notifications" to "unavailable",
                    ))
                    "openAppSettings" -> open(appSettings(), result)
                    "openPermissionSettings" -> when (permission) {
                        "accessibility" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result)
                        "camera" -> open(appSettings(), result)
                        "usage" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result)
                        else -> result.error("UNAVAILABLE", "Settings unavailable", null)
                    }
                    "request" -> when (permission) {
                        "accessibility" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result)
                        "camera" -> requestCamera(result)
                        "usage" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result)
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

    private fun appSettings() = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", activity.packageName, null),
    )

    private fun open(intent: Intent, result: MethodChannel.Result) {
        activity.startActivity(intent)
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

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != cameraRequestCode) return
        val request = pendingCameraRequest
        pendingCameraRequest = null
        request?.success(null) // The Flutter view re-reads state after consent or denial.
    }

    fun dispose() {
        pendingCameraRequest?.error("DETACHED", "Activity detached", null)
        pendingCameraRequest = null
        channel.setMethodCallHandler(null)
    }
}
