package com.scrollcontrol.scroll_control.blocker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel `scroll_control/blocker`: the Dart side's only way to reach
 * the blocking service. Opening a settings page is the only thing it does for
 * permissions; it never grants one.
 */
class BlockerChannel(private val activity: Activity, messenger: BinaryMessenger) {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("BLOCKER_ERROR", e.localizedMessage, null)
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val ctx: Context = activity.applicationContext
        when (call.method) {
            "permissions" -> result.success(
                mapOf(
                    "usageAccess" to BlockerPermissions.hasUsageAccess(ctx),
                    "overlay" to BlockerPermissions.hasOverlay(ctx),
                    "notifications" to notificationsEnabled(ctx),
                ),
            )

            "status" -> result.success(
                mapOf(
                    "serviceRunning" to BlockerService.running,
                    "batteryOptimized" to BlockerPermissions.isBatteryOptimized(ctx),
                    "suspendedReason" to BlockerStore.suspendedReason(ctx),
                ),
            )

            "openOverlaySettings" -> {
                open(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")),
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION),
                )
                result.success(null)
            }

            "openUsageSettings" -> {
                open(
                    Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${ctx.packageName}")),
                    Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
                )
                result.success(null)
            }

            "openBatterySettings" -> {
                open(
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")),
                )
                result.success(null)
            }

            "applySnapshot" -> {
                val json = call.arguments as? String
                if (json == null) {
                    result.error("INVALID_ARGS", "snapshot JSON is required", null)
                } else {
                    BlockerStore.saveSnapshotJson(ctx, json)
                    result.success(null)
                }
            }

            "startService" -> {
                if (!BlockerPermissions.ready(ctx)) {
                    result.error("PERMISSION_DENIED", "Usage Access and overlay permission are required", null)
                    return
                }
                try {
                    BlockerStore.setServiceWanted(ctx, true)
                    BlockerService.start(ctx)
                    result.success(null)
                } catch (e: IllegalStateException) {
                    // ForegroundServiceStartNotAllowedException is a subclass:
                    // Android refuses background starts under its restrictions.
                    result.error("BACKGROUND_RESTRICTED", e.localizedMessage, null)
                } catch (e: SecurityException) {
                    result.error("BACKGROUND_RESTRICTED", e.localizedMessage, null)
                }
            }

            "stopService" -> {
                BlockerStore.setServiceWanted(ctx, false)
                BlockerService.stop(ctx)
                result.success(null)
            }

            "launchableApps" -> result.success(launchableApps(ctx))

            "consumePendingRoute" -> result.success(BlockerStore.consumePendingRoute(ctx))

            else -> result.notImplemented()
        }
    }

    private fun launchableApps(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val exempt = ExemptApps.compute(ctx)
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val pkg = info.activityInfo?.packageName ?: return@mapNotNull null
                if (pkg in exempt) return@mapNotNull null
                mapOf("packageName" to pkg, "appName" to info.loadLabel(pm).toString())
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["appName"]!!.lowercase() }
    }

    private fun notificationsEnabled(ctx: Context): Boolean =
        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
            .areNotificationsEnabled()

    /** Tries [primary]; falls back to [fallback] when the device has no such screen. */
    private fun open(primary: Intent, fallback: Intent) {
        try {
            activity.startActivity(primary)
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(fallback)
        }
    }

    private companion object {
        const val CHANNEL = "scroll_control/blocker"
    }
}
