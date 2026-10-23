package com.scrollcontrol.scroll_control.blocker

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Native persistence for the blocker. Lives in its own preferences file so it
 * is readable by the service and the boot receiver without a Flutter engine.
 */
object BlockerStore {
    private const val PREFS = "scroll_control_blocker"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_WANTED = "service_wanted"
    private const val KEY_SUSPENDED = "suspended_reason"
    private const val KEY_ROUTE = "pending_route"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveSnapshotJson(ctx: Context, json: String) {
        prefs(ctx).edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun loadSnapshot(ctx: Context): Snapshot {
        val raw = prefs(ctx).getString(KEY_SNAPSHOT, null) ?: return Snapshot.EMPTY
        return try {
            parse(JSONObject(raw))
        } catch (_: Exception) {
            Snapshot.EMPTY // corrupt data must never crash the service
        }
    }

    /** Whether the user's setup calls for the service to be running. */
    fun isServiceWanted(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_WANTED, false)

    fun setServiceWanted(ctx: Context, wanted: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_WANTED, wanted).apply()
    }

    fun suspendedReason(ctx: Context): String? = prefs(ctx).getString(KEY_SUSPENDED, null)

    fun setSuspendedReason(ctx: Context, reason: String?) {
        prefs(ctx).edit().apply {
            if (reason == null) remove(KEY_SUSPENDED) else putString(KEY_SUSPENDED, reason)
        }.apply()
    }

    fun setPendingRoute(ctx: Context, route: String) {
        prefs(ctx).edit().putString(KEY_ROUTE, route).apply()
    }

    fun consumePendingRoute(ctx: Context): String? {
        val p = prefs(ctx)
        val route = p.getString(KEY_ROUTE, null)
        if (route != null) p.edit().remove(KEY_ROUTE).apply()
        return route
    }

    private fun parse(json: JSONObject): Snapshot {
        val limits = ArrayList<AppLimitRule>()
        json.optJSONArray("appLimits")?.let { arr ->
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                limits += AppLimitRule(
                    o.getString("pkg"),
                    o.optString("name", o.getString("pkg")),
                    o.getLong("limitSec"),
                )
            }
        }

        val breaks = HashMap<String, Long>()
        json.optJSONArray("breaks")?.let { arr ->
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                breaks[o.getString("pkg")] = o.getLong("untilMs")
            }
        }

        val session = json.optJSONObject("session")?.let { s ->
            val apps = LinkedHashMap<String, String>()
            s.optJSONArray("apps")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    apps[o.getString("pkg")] = o.optString("name", o.getString("pkg"))
                }
            }
            SessionRule(s.getLong("endsAtMs"), apps)
        }

        return Snapshot(
            dailyEnabled = json.optBoolean("dailyEnabled", false),
            globalLimitSec = if (json.isNull("globalLimitSec")) null else json.optLong("globalLimitSec"),
            appLimits = limits,
            breaksUntilMs = breaks,
            session = session,
        )
    }
}
