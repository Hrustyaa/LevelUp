package com.levelup.levelup_test

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * LevelUp v3: an opt-in, best-effort app gate for Android.
 *
 * Key change from v2: the gate is LATCHED. When a blocked target is detected,
 * keep the overlay visible while bouncing the underlying app to HOME.
 * Launcher/overlay/focus events must NOT dismiss the gate. Only a user action,
 * disabling the gate, a new target, an unlock grant, or the lock screen does.
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

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
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

        // v2 BUG: changing focus from the target to the overlay/launcher
        // caused a dismissal, followed by another display -> visible flashing.
        // While latched, ignore window changes; reevaluate only explicit rules.
        if (gateView != null) {
            reevaluate()
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
        clearGate("service interrupted")
    }

    /** Invoked by the existing MainActivity MethodChannel after state changes. */
    fun reevaluate() {
        if (!prefs.getBoolean("enabled", false)) {
            clearGate("disabled")
            return
        }
        if (keyguardManager.isKeyguardLocked) {
            clearGate("keyguard")
            return
        }

        val target = prefs.getString("target", "com.google.android.youtube")
            ?: "com.google.android.youtube"
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

        latchGate(target)
    }

    private fun latchGate(target: String) {
        if (gateView != null) return
        val root = createGateView()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        try {
            windowManager.addView(root, params)
            gateView = root
            gatedPackage = target
            Log.i(TAG, "GATE_LATCHED target=$target")
            // Critical for audio: bring the media app to the background.
            // This generally pauses its regular video/audio playback.
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

    private fun createGateView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(30.dp, 20.dp, 30.dp, 20.dp)
            setBackgroundColor(Color.rgb(17, 22, 26))
            isClickable = true
            isFocusable = true
        }
        fun line(value: String, size: Float, bold: Boolean = false) =
            TextView(this).apply {
                text = value
                textSize = size
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                if (bold) setTypeface(typeface, Typeface.BOLD)
                setPadding(6.dp, 10.dp, 6.dp, 10.dp)
            }
        root.addView(line("LEVELUP", 22f, true))
        root.addView(line("Move to unlock", 26f, true))
        root.addView(line("5 squats = 5 minutes. The distracting app is moved to the background during this challenge.", 16f))

        root.addView(Button(this).apply {
            text = "Start challenge"
            setOnClickListener {
                prefs.edit().putBoolean("open_challenge", true).apply()
                beginNavigationAwayFromGate()
                try {
                    startActivity(Intent(this@LevelUpAccessibilityService, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    })
                } catch (e: Exception) {
                    Log.e(TAG, "Cannot launch challenge", e)
                    prefs.edit().putBoolean("open_challenge", false).apply()
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
        })
        root.addView(Button(this).apply {
            text = "Return home (skip)"
            setOnClickListener {
                beginNavigationAwayFromGate()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        })
        root.addView(Button(this).apply {
            text = "Turn off restriction"
            setOnClickListener {
                prefs.edit().putBoolean("enabled", false).apply()
                beginNavigationAwayFromGate()
                performGlobalAction(GLOBAL_ACTION_HOME)
                Log.i(TAG, "Disabled by user")
            }
        })
        return root
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
        handler.removeCallbacks(poll)
        clearGate("service destroyed")
        instance = null
        super.onDestroy()
    }

    private val Int.dp: Int get() = (this * resources.displayMetrics.density).toInt()
}
