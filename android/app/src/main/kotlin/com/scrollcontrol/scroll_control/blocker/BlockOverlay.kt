package com.scrollcontrol.scroll_control.blocker

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.format.DateFormat
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Date
import kotlin.math.max

/**
 * The block screen: a native overlay drawn over the restricted app.
 *
 * It is a plain [WindowManager] view, so it needs no second Flutter engine
 * (cheap on 1-2 GB devices). It covers the app but not the status bar or
 * navigation bar, so Home, Back and Recents keep working, and it always
 * offers a button to leave. Main thread only.
 */
class BlockOverlay(
    private val ctx: Context,
    private val onGoHome: () -> Unit,
    private val onManage: () -> Unit,
) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var view: View? = null
    private var shownKey: String? = null

    val isShowing: Boolean get() = view != null

    fun show(decision: Decision, displayName: String) {
        val key = "${decision.pkg}|${decision.reason}|${decision.expiresAtMs}"
        if (view != null && shownKey == key) return
        hide()

        val root = build(decision, displayName)
        val type = if (Build.VERSION.SDK_INT >= 26) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // Not focusable: the overlay never steals the keyboard or key
            // events, so Back/Home behave normally.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        )
        try {
            wm.addView(root, params)
            view = root
            shownKey = key
        } catch (_: Exception) {
            // Overlay permission vanished mid-flight; the service re-checks it.
            view = null
            shownKey = null
        }
    }

    fun hide() {
        val v = view ?: return
        view = null
        shownKey = null
        try {
            wm.removeViewImmediate(v)
        } catch (_: Exception) {
            // Already detached.
        }
    }

    // ── View construction ────────────────────────────────────────────────────

    private fun build(d: Decision, displayName: String): View {
        val dark = (ctx.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val bg = if (dark) Color.parseColor("#0A0A0A") else Color.parseColor("#FAFAFA")
        val fg = if (dark) Color.parseColor("#F5F5F5") else Color.parseColor("#111111")
        val muted = if (dark) Color.parseColor("#A0A0A0") else Color.parseColor("#5F5F5F")
        val accent = Color.parseColor("#6C63FF")

        val column = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            val pad = dp(28)
            setPadding(pad, dp(72), pad, dp(72))
        }

        try {
            val icon = ImageView(ctx).apply {
                setImageDrawable(ctx.packageManager.getApplicationIcon(d.pkg))
            }
            column.addView(icon, LinearLayout.LayoutParams(dp(72), dp(72)))
        } catch (_: Exception) {
            // No icon for this package; the text still explains everything.
        }

        column.addView(text("App blocked", 24f, fg, bold = true, topDp = 20))
        column.addView(text(displayName, 18f, fg, topDp = 8))
        column.addView(text(reasonText(d, displayName), 15f, muted, topDp = 16))
        column.addView(text(expiryText(d), 15f, muted, topDp = 8))

        column.addView(
            button("Go to home screen", accent, Color.WHITE) { onGoHome() },
            buttonParams(topDp = 36),
        )
        column.addView(
            button("Manage in ScrollControl", Color.TRANSPARENT, accent, outlined = accent) { onManage() },
            buttonParams(topDp = 12),
        )

        return FrameLayout(ctx).apply {
            setBackgroundColor(bg)
            // Swallow touches so the blocked app underneath cannot be used.
            isClickable = true
            addView(
                column,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
        }
    }

    private fun reasonText(d: Decision, name: String): String = when (d.reason) {
        Reason.SESSION ->
            "A Focus Session is in progress, so $name is blocked until it ends."
        Reason.DAILY_APP ->
            "You've reached your daily limit for $name: " +
                "${minutes(d.usedSec)} used of ${minutes(d.limitSec)}."
        Reason.DAILY_TOTAL ->
            "You've reached your total daily screen-time limit: " +
                "${minutes(d.usedSec)} used of ${minutes(d.limitSec)}."
    }

    private fun expiryText(d: Decision): String {
        val time = DateFormat.getTimeFormat(ctx).format(Date(d.expiresAtMs))
        val minutesLeft = max(1L, (d.expiresAtMs - System.currentTimeMillis()) / 60_000L)
        return when (d.reason) {
            Reason.SESSION -> "Available again at $time (in about $minutesLeft min)."
            else -> "Your limit resets at midnight, in about ${formatDuration(minutesLeft)}."
        }
    }

    private fun minutes(seconds: Long?): String = "${(seconds ?: 0L) / 60} min"

    private fun formatDuration(totalMinutes: Long): String {
        val h = totalMinutes / 60
        val m = totalMinutes % 60
        return if (h > 0) "${h}h ${m}m" else "${m}m"
    }

    private fun text(
        value: String,
        sizeSp: Float,
        color: Int,
        bold: Boolean = false,
        topDp: Int = 0,
    ): TextView = TextView(ctx).apply {
        text = value
        textSize = sizeSp
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(topDp) }
    }

    private fun button(
        label: String,
        fill: Int,
        textColor: Int,
        outlined: Int? = null,
        onClick: () -> Unit,
    ): Button = Button(ctx).apply {
        text = label
        isAllCaps = false
        setTextColor(textColor)
        background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(fill)
            if (outlined != null) setStroke(dp(1), outlined)
        }
        setOnClickListener { onClick() }
    }

    private fun buttonParams(topDp: Int) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        dp(52),
    ).apply { topMargin = dp(topDp) }

    private fun dp(value: Int): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
