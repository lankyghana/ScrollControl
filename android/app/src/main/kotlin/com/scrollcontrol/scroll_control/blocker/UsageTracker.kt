package com.scrollcontrol.scroll_control.blocker

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager

/**
 * Tracks the foreground app and today's per-app foreground time from
 * [UsageStatsManager] events.
 *
 * It reads each event once (a moving cursor), so a poll only touches the few
 * events since the last one. Accumulating from events, rather than the
 * aggregated stats API, means the app currently on screen counts up to "now"
 * instead of only after it leaves the foreground.
 *
 * Not thread-safe: use from a single thread.
 */
class UsageTracker(private val usm: UsageStatsManager) {

    private val accumulatedMs = HashMap<String, Long>()
    private val openSinceMs = HashMap<String, Long>()
    private var dayStartMs = -1L
    private var cursorMs = 0L

    /** Package currently in the foreground, or null if unknown / screen off. */
    var foreground: String? = null
        private set

    /**
     * Applies events up to [nowMs]. When [dayStartMs] changes (local
     * midnight), usage restarts from zero, which is what resets daily limits.
     */
    fun refresh(nowMs: Long, dayStartMs: Long) {
        if (dayStartMs != this.dayStartMs) {
            val stillOpen = openSinceMs.keys.toList()
            accumulatedMs.clear()
            openSinceMs.clear()
            // An app already open across midnight keeps counting from 00:00.
            stillOpen.forEach { openSinceMs[it] = dayStartMs }
            this.dayStartMs = dayStartMs
            // Look back a little so an app opened before the day began is seen.
            if (cursorMs == 0L) cursorMs = dayStartMs - LOOKBACK_MS
        }

        val events = try {
            usm.queryEvents(cursorMs, nowMs)
        } catch (_: SecurityException) {
            null // permission was just revoked; the service notices separately
        } ?: return

        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            val ts = event.timeStamp
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    if (!openSinceMs.containsKey(pkg)) openSinceMs[pkg] = ts
                    foreground = pkg
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    close(pkg, ts)
                    if (foreground == pkg) foreground = null
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    openSinceMs.keys.toList().forEach { close(it, ts) }
                    foreground = null
                }
            }
            if (ts + 1 > cursorMs) cursorMs = ts + 1
        }
    }

    /** Today's foreground seconds per package, including time still open. */
    fun usedSecondsByPackage(nowMs: Long): Map<String, Long> {
        val result = HashMap<String, Long>(accumulatedMs.size + openSinceMs.size)
        for ((pkg, ms) in accumulatedMs) result[pkg] = ms / 1000L
        for ((pkg, since) in openSinceMs) {
            val open = (nowMs - maxOf(since, dayStartMs)).coerceAtLeast(0L)
            result[pkg] = ((accumulatedMs[pkg] ?: 0L) + open) / 1000L
        }
        return result
    }

    private fun close(pkg: String, ts: Long) {
        val since = openSinceMs.remove(pkg) ?: return
        val duration = ts - maxOf(since, dayStartMs)
        if (duration > 0L) accumulatedMs[pkg] = (accumulatedMs[pkg] ?: 0L) + duration
    }

    private companion object {
        const val LOOKBACK_MS = 6L * 60 * 60 * 1000
    }
}
