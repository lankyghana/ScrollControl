package com.scrollcontrol.scroll_control

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Process
import android.provider.Settings
import com.scrollcontrol.scroll_control.blocker.BlockerChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "scroll_control/usage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // App-blocking bridge (permissions, service control, app list).
        BlockerChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Check if the user granted Usage Access ─────────────────
                    "hasUsagePermission" -> {
                        result.success(hasUsagePermission())
                    }

                    // ── Fetch aggregated usage stats for a time window ─────────
                    "getUsageStats" -> {
                        if (!hasUsagePermission()) {
                            result.error(
                                "PERMISSION_DENIED",
                                "Usage access not granted. Open Settings > Apps > Special app access > Usage access.",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val startTime = call.argument<Long>("startTime")
                        val endTime   = call.argument<Long>("endTime")

                        if (startTime == null || endTime == null) {
                            result.error("INVALID_ARGS", "startTime and endTime are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(getUsageStats(startTime, endTime))
                        } catch (e: Exception) {
                            result.error("QUERY_ERROR", e.localizedMessage, null)
                        }
                    }

                    // ── Foreground app detection ───────────────────────────────
                    "getForegroundApp" -> {
                        if (!hasUsagePermission()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(getForegroundApp())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }

                    // ── Open Usage Access settings page ───────────────────────
                    "openUsageSettings" -> {
                        try {
                            // Android 10+: jump directly to this app's entry
                            val intent = Intent(
                                Settings.ACTION_USAGE_ACCESS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        } catch (_: ActivityNotFoundException) {
                            // Older Android: open the general Usage Access list
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        }
                        result.success(null)
                    }

                    // ── Installed version, e.g. "1.0.0 (1)" ──────────────────
                    "getAppVersion" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            @Suppress("DEPRECATION")
                            val code = if (android.os.Build.VERSION.SDK_INT >= 28) {
                                info.longVersionCode
                            } else {
                                info.versionCode.toLong()
                            }
                            result.success("${info.versionName} ($code)")
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }

                    // ── Fetch app icon as PNG ByteArray ──────────────────────
                    "getAppIcon" -> {
                        val pkgName = call.argument<String>("packageName")
                        if (pkgName == null) {
                            result.error("INVALID_ARGS", "packageName is required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val iconBytes = getAppIconBytes(pkgName)
                            result.success(iconBytes)
                        } catch (e: Exception) {
                            result.success(null) // Return null on error (not a crash)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Returns true when the app has been granted "Usage Access" by the user
     * (Settings > Apps > Special app access > Usage access).
     * Uses AppOpsManager so it works on API 21+.
     */
    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Queries [UsageStatsManager] for the given time window.
     *
     * [queryAndAggregateUsageStats] already collapses all intervals into one
     * entry per package — no de-duplication needed on the Dart side.
     *
     * Only entries with foreground time > 0 are included.
     * System packages without a visible label are silently skipped.
     *
     * Returns a list of maps compatible with Dart's Map<dynamic, dynamic>:
     *   { "packageName": String, "appName": String, "usageTime": Long (seconds) }
     */
    private fun getUsageStats(startTime: Long, endTime: Long): List<Map<String, Any>> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm  = packageManager

        // Aggregated map: packageName → UsageStats (already merged across intervals)
        val aggregated = usm.queryAndAggregateUsageStats(startTime, endTime)

        return aggregated.values
            .filter { it.totalTimeInForeground > 0L }
            .mapNotNull { stat ->
                val appName = resolveAppName(pm, stat.packageName) ?: return@mapNotNull null
                mapOf(
                    "packageName" to stat.packageName,
                    "appName"     to appName,
                    // Convert ms → seconds; cap at Long to avoid Int overflow
                    "usageTime"   to (stat.totalTimeInForeground / 1_000L)
                )
            }
            .sortedByDescending { it["usageTime"] as Long }
    }

    /**
     * Returns the package name of the app currently in the foreground by
     * querying the last 60 seconds of usage stats and picking the entry
     * with the most recent [lastTimeUsed] timestamp.
     *
     * Returns null when permission is denied or no foreground app is found.
     */
    private fun getForegroundApp(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            now - 60_000L, // last 60 seconds
            now
        ) ?: return null
        return stats
            .filter { it.totalTimeInForeground > 0L }
            .maxByOrNull { it.lastTimeUsed }
            ?.packageName
    }

    /**
     * Resolves a human-readable app name from a package name.
     * Returns null for packages that are uninstalled or invisible to the user.
     */
    private fun resolveAppName(pm: PackageManager, packageName: String): String? {
        return try {
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            null // Skip uninstalled / hidden packages
        }
    }

    /**
     * Fetches the app icon for a given package name and converts it to a PNG ByteArray.
     * Returns null if the package is not found or has no icon.
     */
    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val pm = packageManager
            val drawable = pm.getApplicationIcon(packageName)
            drawableToPngBytes(drawable)
        } catch (e: PackageManager.NameNotFoundException) {
            null // Package not found
        } catch (e: Exception) {
            null // Any other error
        }
    }

    /**
     * Converts a Drawable to a PNG ByteArray.
     * If the drawable is already a BitmapDrawable, uses it directly.
     * Otherwise, rasterizes it on a canvas.
     */
    private fun drawableToPngBytes(drawable: Drawable): ByteArray? {
        return try {
            val bitmap = if (drawable is android.graphics.drawable.BitmapDrawable) {
                drawable.bitmap
            } else {
                // Rasterize vector/scalable drawable
                val width = drawable.intrinsicWidth.coerceAtLeast(1)
                val height = drawable.intrinsicHeight.coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap
            }

            // Downscale: icons are shown at a few dozen dp, and full-size
            // adaptive icons cost tens of KB each (matters on 1-2 GB devices).
            val maxSide = 96
            val scaled = if (bitmap.width > maxSide || bitmap.height > maxSide) {
                val ratio = maxSide.toFloat() / maxOf(bitmap.width, bitmap.height)
                Bitmap.createScaledBitmap(
                    bitmap,
                    maxOf(1, (bitmap.width * ratio).toInt()),
                    maxOf(1, (bitmap.height * ratio).toInt()),
                    true
                )
            } else {
                bitmap
            }

            // Compress bitmap to PNG
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }
    }
}
