package com.levelup.levelup_test

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

/** Layout only. Never changes Focus state or grants access. */
internal object LevelUpGateV2View {
    private val bg = Color.rgb(10, 15, 16)
    private val surface = Color.rgb(17, 23, 24)
    private val lime = Color.rgb(199, 250, 91)
    private val white = Color.rgb(247, 248, 248)
    private val muted = Color.rgb(176, 184, 186)
    private val border = Color.rgb(41, 51, 52)

    /**
     * Existing service owns foreground package validation, gate display,
     * safe Home/Back escape, voluntary Focus disable and onStart behavior.
     * The exit button also works when the overlay leaves Android navigation gestures enabled.
     */
    fun create(
        context: Context,
        targetPackageName: String,
        language: String,
        repetitions: Int,
        accessMinutes: Int,
        onExit: () -> Unit,
        onStart: () -> Unit,
    ): View {
        require(repetitions > 0 && accessMinutes > 0)
        fun tr(ru: String, en: String, kk: String) = when (language) {
            "en" -> en
            "kk" -> kk
            else -> ru
        }
        fun dp(value: Int): Int = (context.resources.displayMetrics.density * value + 0.5f).toInt()
        fun label(value: String, sp: Float, color: Int, bold: Boolean = false): TextView =
            TextView(context).apply {
                text = value
                textSize = sp
                setTextColor(color)
                gravity = Gravity.CENTER
                includeFontPadding = false
                if (bold) setTypeface(typeface, Typeface.BOLD)
            }
        fun space(height: Int = 0, weight: Float = 0f): View = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(1, if (weight > 0f) 0 else dp(height), weight)
        }
        fun rounded(fill: Int, borderColor: Int = border, radius: Int = 12) =
            GradientDrawable().apply {
                setColor(fill)
                setStroke(dp(1), borderColor)
                cornerRadius = dp(radius).toFloat()
            }

        val packageManager = context.packageManager
        val info = try {
            packageManager.getApplicationInfo(targetPackageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        val appName = info?.let { packageManager.getApplicationLabel(it).toString() }
            ?: targetPackageName.substringAfterLast('.')
        val appIcon = try {
            packageManager.getApplicationIcon(targetPackageName)
        } catch (_: PackageManager.NameNotFoundException) {
            context.getDrawable(android.R.drawable.sym_def_app_icon)
        }

        val root = BackDismissibleGate(context, onExit).apply {
            isFillViewport = true
            setBackgroundColor(bg)
            isFocusableInTouchMode = true
            setOnApplyWindowInsetsListener { view, insets ->
                @Suppress("DEPRECATION")
                view.setPadding(0, insets.systemWindowInsetTop, 0, insets.systemWindowInsetBottom)
                insets
            }
        }
        val page = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(20), dp(24), dp(22))
        }
        root.addView(page, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        page.addView(label("LevelUp", 21f, white, true).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
        }.apply { minHeight = dp(40) }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        page.addView(space(weight = 1f))

        val image = ImageView(context).apply {
            setImageDrawable(appIcon)
            scaleType = ImageView.ScaleType.FIT_CENTER
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            background = rounded(surface)
            setPadding(dp(8), dp(8), dp(8), dp(8))
        }
        page.addView(image, LinearLayout.LayoutParams(dp(88), dp(88)))
        page.addView(space(24))
        page.addView(label(
            tr("$appName на паузе", "$appName is paused", "$appName кідіртілді"),
            27f, white, true
        ))
        page.addView(space(12))
        page.addView(label(tr(
            "Чтобы продолжить, выполни короткое задание.",
            "Complete a short task to continue.",
            "Жалғастыру үшін қысқа тапсырманы орында."
        ), 15f, muted))
        page.addView(space(26))

        val exercise = label(tr(
            "Упражнение · $repetitions повторений",
            "Exercise · $repetitions reps",
            "Жаттығу · $repetitions рет"
        ), 19f, white, true).apply {
            background = rounded(surface)
            setPadding(dp(16), dp(20), dp(16), dp(20))
        }
        page.addView(exercise, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        page.addView(space(14))
        page.addView(label(tr(
            "После выполнения получишь $accessMinutes минут доступа.",
            "Finish to get $accessMinutes minutes of access.",
            "Аяқтаған соң $accessMinutes минут қолжетімділік беріледі."
        ), 13f, muted))
        page.addView(space(weight = 1f))

        val button = Button(context).apply {
            text = tr("Начать задание", "Start challenge", "Тапсырманы бастау")
            isAllCaps = false
            textSize = 16f
            setTextColor(bg)
            setTypeface(typeface, Typeface.BOLD)
            minHeight = dp(54)
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = RippleDrawable(ColorStateList.valueOf(0x260A0F10), rounded(lime, lime), null)
            setOnClickListener { onStart() }
        }
        page.addView(button, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        page.addView(label(tr("Назад", "Go Back", "Артқа"), 14f, muted, true).apply {
            minHeight = dp(48)
            isClickable = true
            isFocusable = true
            setOnClickListener { onExit() }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        root.requestApplyInsets()
        return root
    }

    private class BackDismissibleGate(context: Context, private val onExit: () -> Unit) :
        ScrollView(context) {
        private var unregisterBack: (() -> Unit)? = null
        private var hadWindowFocus = false

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (Build.VERSION.SDK_INT >= 33) {
                val dispatcher = findOnBackInvokedDispatcher()
                if (dispatcher != null) {
                    val callback = OnBackInvokedCallback { onExit() }
                    dispatcher.registerOnBackInvokedCallback(
                        OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback,
                    )
                    unregisterBack = { dispatcher.unregisterOnBackInvokedCallback(callback) }
                }
            }
            requestFocus()
        }

        override fun onDetachedFromWindow() {
            unregisterBack?.invoke()
            unregisterBack = null
            super.onDetachedFromWindow()
        }

        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode != KeyEvent.KEYCODE_BACK) return super.dispatchKeyEvent(event)
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) onExit()
            return true
        }

        override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
            super.onWindowFocusChanged(hasWindowFocus)
            if (hasWindowFocus) {
                hadWindowFocus = true
            } else if (hadWindowFocus) {
                post {
                    if (isAttachedToWindow && !hasWindowFocus()) onExit()
                }
            }
        }
    }
}
