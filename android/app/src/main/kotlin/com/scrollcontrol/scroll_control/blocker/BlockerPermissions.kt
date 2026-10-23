package com.scrollcontrol.scroll_control.blocker

import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings

/** Read-only checks of the permissions blocking depends on. Never grants anything. */
object BlockerPermissions {

    /** Usage Access: needed to see which app is in the foreground. */
    fun hasUsageAccess(ctx: Context): Boolean {
        val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** "Display over other apps": needed to show the block screen. */
    fun hasOverlay(ctx: Context): Boolean = Settings.canDrawOverlays(ctx)

    fun ready(ctx: Context): Boolean = hasUsageAccess(ctx) && hasOverlay(ctx)

    /** True when Android may restrict this app in the background (advisory). */
    fun isBatteryOptimized(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return !pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }
}
