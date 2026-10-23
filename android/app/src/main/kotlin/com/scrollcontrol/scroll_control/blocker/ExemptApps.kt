package com.scrollcontrol.scroll_control.blocker

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.telecom.TelecomManager
import android.view.inputmethod.InputMethodManager

/**
 * Packages that are never blocked, so the restriction can never lock the user
 * out of the phone: the launcher, the dialer and emergency functions, system
 * settings and UI, keyboards, permission dialogs and ScrollControl itself
 * (where the user manages their restrictions).
 */
object ExemptApps {

    private val ALWAYS = setOf(
        "android",
        "com.android.systemui",
        "com.android.settings",
        "com.android.phone",
        "com.android.server.telecom",
        "com.android.emergency",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    /** Computes the exemption set; call occasionally, not on every poll. */
    fun compute(ctx: Context): Set<String> {
        val result = HashSet<String>(ALWAYS)
        result += ctx.packageName

        try {
            val pm = ctx.packageManager
            val home = pm.resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY,
            )
            home?.activityInfo?.packageName?.let { result += it }

            val telecom = ctx.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            telecom?.defaultDialerPackage?.let { result += it }

            val imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.enabledInputMethodList?.forEach { result += it.packageName }
        } catch (_: Exception) {
            // Best effort: the static list above still protects the essentials.
        }
        return result
    }
}
