package com.levelup.levelup_test

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Button
import android.widget.ScrollView
import android.widget.TextView
import java.util.Locale

/**
 * LevelUp v3: an opt-in, best-effort app gate for Android.
 *
 * Key design invariant:
 * - The gate overlay sits directly over the blocked target without calling
 *   GLOBAL_ACTION_HOME on latch, so the blocked app remains the underlying
 *   TYPE_APPLICATION window until the user leaves it.
 * - Swiping Home, switching via Recents, or opening LevelUp / any unrestricted
 *   app changes the foreground TYPE_APPLICATION window and immediately
 *   dismisses the overlay via [GateLifecyclePolicy].
 * - Unrelated system windows (notifications, volume, permission dialogs) never
 *   dismiss the gate.
 */
class LevelUpAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "LevelUpGate"
        private const val POLL_INTERVAL_MS = 1000L
        private const val NAVIGATION_GRACE_MS = 1800L
        private const val DEFAULT_TARGET = "com.google.android.youtube"

        private val TARGET_DISPLAY_NAMES = mapOf(
            "com.google.android.youtube" to "YouTube",
            "com.instagram.android" to "Instagram",
            "com.zhiliaoapp.musically" to "TikTok",
        )

        @Volatile
        var instance: LevelUpAccessibilityService? = null
            private set
    }

    private val prefs by lazy { getSharedPreferences("levelup_gate", Context.MODE_PRIVATE) }
    private val flutterPrefs by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }
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
            if (prefs.getBoolean("enabled", false)) {
                foregroundFromWindows()?.let { updateForeground(it, "poll") }
            }
            reevaluate()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        clearGate("service connected")
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
        Log.i(TAG, "Connected v3: fullscreen LevelUp gate + Home-gesture safe lifecycle")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !monitoring) return
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return

        val eventPackage = event.packageName?.toString()
        val resolved = if (gateView != null) {
            // While the gate is latched, ignore raw event.packageName from our own
            // TYPE_ACCESSIBILITY_OVERLAY or transient system windows; inspect
            // authoritative TYPE_APPLICATION windows instead.
            foregroundFromWindows()
        } else {
            when {
                eventPackage == packageName -> foregroundFromWindows() ?: packageName
                type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                    isCandidateApplication(eventPackage) -> eventPackage
                else -> foregroundFromWindows()
            }
        }
        if (resolved != null) updateForeground(resolved, "event=$type")
        reevaluate()
    }

    override fun onInterrupt() {
        clearGate("service interrupted")
    }

    /** Invoked by MainActivity MethodChannel or lifecycle events after state changes. */
    fun reevaluate() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { reevaluate() }
            return
        }

        val target = prefs.getString("target", DEFAULT_TARGET) ?: DEFAULT_TARGET
        val fg = foregroundPackage
        val snapshot = GateStateSnapshot(
            focusEnabled = prefs.getBoolean("enabled", false),
            isKeyguardLocked = keyguardManager.isKeyguardLocked,
            selectedTarget = target,
            unlockUntilMs = prefs.getLong("unlock_until", 0L),
            nowMs = System.currentTimeMillis(),
            uptimeMs = SystemClock.uptimeMillis(),
            foregroundPackage = fg,
            isForegroundCandidateApp = isCandidateApplication(fg),
            gatedPackage = gatedPackage,
            ignoreReentryUntilUptimeMs = ignoreReentryUntil,
        )

        when (val action = GateLifecyclePolicy.evaluate(snapshot)) {
            is GateAction.None -> Unit
            is GateAction.DismissGate -> clearGate(action.reason)
            is GateAction.ShowGate -> latchGate(action.targetPackage)
        }
    }

    private fun latchGate(target: String) {
        if (gateView != null) return
        val root = createGateView(target)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        } else {
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        try {
            windowManager.addView(root, params)
            gateView = root
            gatedPackage = target
            Log.i(TAG, "GATE_LATCHED target=$target")
        } catch (e: Exception) {
            gateView = null
            gatedPackage = null
            Log.e(TAG, "Failed to display gate (fails open)", e)
        }
    }

    private fun createGateView(target: String): View {
        val root = LayoutInflater.from(this).inflate(R.layout.view_levelup_gate, null)
        val scrollView = root.findViewById<ScrollView>(R.id.gate_scroll)
        applySystemInsets(scrollView)

        val lang = resolveLanguage()
        val appName = resolveTargetDisplayName(target)

        root.findViewById<TextView>(R.id.gate_focus_label).text = tr(
            lang,
            en = "FOCUS MODE",
            ru = "РЕЖИМ ФОКУСА",
            kk = "ФОКУС РЕЖИМІ",
        )
        root.findViewById<TextView>(R.id.gate_headline).text = tr(
            lang,
            en = "Stay focused.",
            ru = "Сохраняй фокус.",
            kk = "Назарды сақта.",
        )
        root.findViewById<TextView>(R.id.gate_target_app).text = appName
        root.findViewById<TextView>(R.id.gate_challenge_title).text = tr(
            lang,
            en = "Squat Challenge · 5 reps",
            ru = "Приседания · 5 повторений",
            kk = "Отырып-тұру · 5 рет",
        )
        root.findViewById<TextView>(R.id.gate_challenge_subtitle).text = tr(
            lang,
            en = "Earn 5 minutes of access by completing 5 verified squats.",
            ru = "Выполни 5 приседаний с проверкой, чтобы получить 5 минут доступа.",
            kk = "5 минут рұқсат алу үшін 5 отырып-тұру жасаңыз.",
        )

        root.findViewById<Button>(R.id.gate_start_button).apply {
            text = tr(
                lang,
                en = "Start Challenge",
                ru = "Начать задание",
                kk = "Тапсырманы бастау",
            )
            setOnClickListener {
                prefs.edit().putBoolean("open_challenge", true).apply()
                beginNavigationAwayFromGate()
                try {
                    startActivity(
                        Intent(this@LevelUpAccessibilityService, MainActivity::class.java).apply {
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            )
                        }
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Cannot launch challenge", e)
                    prefs.edit().putBoolean("open_challenge", false).apply()
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
        }

        root.findViewById<Button>(R.id.gate_back_button).apply {
            text = tr(
                lang,
                en = "Go Back",
                ru = "Назад",
                kk = "Артқа",
            )
            setOnClickListener {
                beginNavigationAwayFromGate()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }

        return root
    }

    private fun applySystemInsets(scrollView: ScrollView) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            scrollView.setOnApplyWindowInsetsListener { v, insets ->
                val bars = insets.getInsets(
                    WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
                )
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                insets
            }
        } else {
            @Suppress("DEPRECATION")
            scrollView.setOnApplyWindowInsetsListener { v, insets ->
                v.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom,
                )
                insets
            }
        }
        scrollView.requestApplyInsets()
    }

    private fun resolveLanguage(): String {
        val saved = flutterPrefs.getString("flutter.levelup.welcome.language", null)
        if (saved == "en" || saved == "ru" || saved == "kk") return saved
        return when (Locale.getDefault().language) {
            "ru" -> "ru"
            "kk" -> "kk"
            else -> "en"
        }
    }

    private fun resolveTargetDisplayName(target: String): String {
        TARGET_DISPLAY_NAMES[target]?.let { return it }
        return try {
            val appInfo = packageManager.getApplicationInfo(target, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            "App"
        }
    }

    private fun tr(lang: String, en: String, ru: String, kk: String): String = when (lang) {
        "ru" -> ru
        "kk" -> kk
        else -> en
    }

    private fun beginNavigationAwayFromGate() {
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
}
