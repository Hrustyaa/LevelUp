package com.levelup.levelup_test

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import java.util.UUID

/**
 * LevelUp v3: an opt-in, best-effort app gate for Android.
 *
 * Key change from v2: the gate is LATCHED. When a blocked target is detected,
 * keep the overlay visible while bouncing the underlying app to HOME.
 * The service's own Home action leaves the gate latched. A later system
 * navigation action or a different foreground activity can release the overlay.
 *
 * HOME typically pauses ordinary video sound because the media app is no longer
 * foreground. It cannot silence apps that deliberately support background
 * playback / PiP. The service never changes device-wide volume.
 *
 * This service reads package names only; no text, screen captures or gestures.
 * It does not block Settings, phone calls or app removal.
 */
class LevelUpAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "LevelUpGate"
        private const val POLL_INTERVAL_MS = 1000L
        private const val NAVIGATION_GRACE_MS = 1800L
        internal const val FOCUS_REPETITIONS = 5
        internal const val FOCUS_ACCESS_MINUTES = 5

        @Volatile
        var instance: LevelUpAccessibilityService? = null
            private set
    }

    private val prefs by lazy { getSharedPreferences("levelup_gate", Context.MODE_PRIVATE) }
    private val windowManager by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }
    private val keyguardManager by lazy { getSystemService(KEYGUARD_SERVICE) as KeyguardManager }
    private val handler = Handler(Looper.getMainLooper())

    private var gateView: View? = null
    private var gatedPackage: String? = null
    private var foregroundPackage: String? = null
    private var ignoreReentryUntil: Long = 0L
    private var monitoring = false
    private var homeReceiverRegistered = false
    private var ignoreHomeUntil = 0L
    private val homePackage by lazy {
        packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName
    }

    // Only receive the system's Home notification. We never send this broadcast.
    @Suppress("DEPRECATION")
    private val homeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (gateView != null && SystemClock.uptimeMillis() >= ignoreHomeUntil &&
                intent?.action == Intent.ACTION_CLOSE_SYSTEM_DIALOGS &&
                intent.getStringExtra("reason") == "homekey") {
                beginNavigationAwayFromGate()
            }
        }
    }

    private data class Challenge(val id: String, val target: String, var claimed: Boolean = false)
    private var challenge: Challenge? = null

    private fun selectedTarget(): String =
        prefs.getString("target", "com.google.android.youtube") ?: "com.google.android.youtube"

    internal fun claimChallenge(): Map<String, String>? {
        val request = challenge ?: return null
        if (request.claimed || !isChallengeAvailable(request)) return null
        request.claimed = true
        return mapOf("id" to request.id, "target" to request.target)
    }

    internal fun cancelChallenge(id: String): Boolean {
        if (challenge?.id != id) return false
        challenge = null
        reevaluate()
        return true
    }

    internal fun invalidateChallenge() {
        challenge = null
    }

    internal fun consumeCompletedChallenge(id: String?, target: String?, repetitions: Int?): Boolean {
        val request = challenge ?: return false
        if (!request.claimed || request.id != id || request.target != target ||
            repetitions != FOCUS_REPETITIONS || !isChallengeAvailable(request)) return false
        challenge = null
        return true
    }

    private fun isChallengeAvailable(request: Challenge): Boolean =
        monitoring && !keyguardManager.isKeyguardLocked &&
            prefs.getBoolean("enabled", false) && request.target == selectedTarget()

    private val poll = object : Runnable {
        override fun run() {
            if (!monitoring) return
            if (gateView == null && prefs.getBoolean("enabled", false)) {
                foregroundFromWindows()?.let { updateForeground(it, "poll") }
            }
            reevaluate()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    @Suppress("DEPRECATION")
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        if (!homeReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(homeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(homeReceiver, filter)
            }
            homeReceiverRegistered = true
        }
        val info = serviceInfo
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_WINDOWS_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        info.notificationTimeout = 0
        serviceInfo = info
        monitoring = true
        handler.removeCallbacks(poll)
        handler.post(poll)
        Log.i(TAG, "Connected v3: latched gate + HOME audio mitigation")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !monitoring) return
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return

        if (gateView != null) {
            val eventPackage = event.packageName?.toString()
            // Ignore the overlay and the launcher exposed by our own Home action.
            // An actual different foreground activity, such as Settings, stays accessible.
            if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                isCandidateApplication(eventPackage) && eventPackage != packageName &&
                eventPackage != gatedPackage && eventPackage != homePackage &&
                (homePackage != null || eventPackage == "com.android.settings" ||
                    eventPackage == "com.samsung.accessibility") &&
                foregroundFromWindows() == eventPackage) {
                beginNavigationAwayFromGate()
            } else {
                reevaluate()
            }
            return
        }

        val eventPackage = event.packageName?.toString()
        val resolved = when {
            eventPackage == packageName -> packageName
            type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                isCandidateApplication(eventPackage) -> eventPackage
            else -> foregroundFromWindows()
        }
        if (resolved != null) updateForeground(resolved, "event=$type")
        reevaluate()
    }

    override fun onInterrupt() {
        // Accessibility services can be interrupted by the OS. Fail open.
        invalidateChallenge()
        clearGate("service interrupted")
    }

    /** Invoked by the existing MainActivity MethodChannel after state changes. */
    fun reevaluate() {
        if (!prefs.getBoolean("enabled", false)) {
            invalidateChallenge()
            clearGate("disabled")
            return
        }
        if (keyguardManager.isKeyguardLocked) {
            invalidateChallenge()
            clearGate("keyguard")
            return
        }

        val target = selectedTarget()
        val unlocked = prefs.getLong("unlock_until", 0L) > System.currentTimeMillis()

        // An existing gate is kept on-screen even after HOME is foreground.
        // Only intentional release conditions may dismiss it.
        if (gateView != null) {
            if (gatedPackage != target || unlocked) {
                clearGate(if (unlocked) "access granted" else "target changed")
            }
            return
        }

        if (SystemClock.uptimeMillis() < ignoreReentryUntil) return
        if (foregroundPackage != target || unlocked) return

        // A permission dialog or our own Activity must not restart the gate.
        // If the target really came forward, abandon the request and gate it.
        if (challenge != null && foregroundFromWindows() != target) return
        invalidateChallenge()
        latchGate(target)
    }

    private fun latchGate(target: String) {
        if (gateView != null) return
        val root = createGateView(target)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            if (Build.VERSION.SDK_INT >= 30) {
                fitInsetsTypes = WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
                isFitInsetsIgnoringVisibility = true
            }
        }
        try {
            windowManager.addView(root, params)
            gateView = root
            gatedPackage = target
            Log.i(TAG, "GATE_LATCHED target=$target")
            // Critical for audio: bring the media app to the background.
            // This generally pauses its regular video/audio playback.
            ignoreHomeUntil = SystemClock.uptimeMillis() + POLL_INTERVAL_MS
            val homeWorked = performGlobalAction(GLOBAL_ACTION_HOME)
            Log.i(TAG, "HOME_ACTION success=$homeWorked target=$target")
            if (!homeWorked) {
                // One bounded retry, never a loop of actions / overlay recreation.
                handler.postDelayed({
                    if (gateView != null && gatedPackage == target) {
                        val retryWorked = performGlobalAction(GLOBAL_ACTION_HOME)
                        Log.i(TAG, "HOME_RETRY success=$retryWorked target=$target")
                    }
                }, 400L)
            }
        } catch (e: Exception) {
            gateView = null
            gatedPackage = null
            Log.e(TAG, "Failed to display gate (fails open)", e)
        }
    }

    private fun createGateView(target: String): View = LevelUpGateV2View.create(
        context = this,
        targetPackageName = target,
        language = prefs.getString("language", "en") ?: "en",
        repetitions = FOCUS_REPETITIONS,
        accessMinutes = FOCUS_ACCESS_MINUTES,
        onExit = {
            if (gatedPackage == target) {
                beginNavigationAwayFromGate()
            }
        },
        onStart = { startChallenge(target) },
    )

    private fun startChallenge(target: String) {
        if (gateView == null || gatedPackage != target || selectedTarget() != target ||
            !prefs.getBoolean("enabled", false)) return

        challenge = Challenge(UUID.randomUUID().toString(), target)
        beginNavigationAwayFromGate()
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            })
        } catch (e: Exception) {
            invalidateChallenge()
            Log.e(TAG, "Cannot launch challenge", e)
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    private fun beginNavigationAwayFromGate() {
        // Avoid treating our own transition as an immediate new blocked launch.
        ignoreReentryUntil = SystemClock.uptimeMillis() + NAVIGATION_GRACE_MS
        foregroundPackage = null
        clearGate("user action")
    }

    private fun clearGate(reason: String) {
        val old = gateView ?: run {
            gatedPackage = null
            return
        }
        gateView = null
        gatedPackage = null
        try {
            windowManager.removeView(old)
            Log.i(TAG, "GATE_RELEASED reason=$reason")
        } catch (e: Exception) {
            Log.w(TAG, "Failed removing gate", e)
        }
    }

    private fun isCandidateApplication(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        if (pkg == "android" || pkg == "com.android.systemui" ||
            pkg == "com.google.android.permissioncontroller" ||
            pkg == "com.android.permissioncontroller") return false
        return true
    }

    /** Reads ONLY the top application's package name; never traverses UI nodes. */
    private fun foregroundFromWindows(): String? {
        return try {
            val candidates = windows.asSequence()
                .filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                .mapNotNull { window ->
                    val pkg = window.root?.packageName?.toString()
                    if (pkg.isNullOrBlank()) null
                    else Triple(pkg, window.isFocused, window.isActive)
                }.toList()
            (candidates.firstOrNull { it.second }
                ?: candidates.firstOrNull { it.third }
                ?: candidates.firstOrNull())?.first
        } catch (e: Exception) {
            Log.w(TAG, "Window package lookup unavailable", e)
            null
        }
    }

    private fun updateForeground(pkg: String, origin: String) {
        if (pkg == foregroundPackage) return
        foregroundPackage = pkg
        Log.d(TAG, "Foreground=$pkg origin=$origin")
    }

    override fun onDestroy() {
        monitoring = false
        invalidateChallenge()
        if (homeReceiverRegistered) {
            unregisterReceiver(homeReceiver)
            homeReceiverRegistered = false
        }
        handler.removeCallbacks(poll)
        clearGate("service destroyed")
        instance = null
        super.onDestroy()
    }
}
