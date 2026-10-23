package com.scrollcontrol.scroll_control.blocker

/**
 * Pure restriction rules. No Android dependencies, so it can be unit-tested
 * on the JVM.
 *
 * This is a mirror of `BlockSnapshot.decide` in
 * `lib/features/blocking/domain/block_snapshot.dart`. The native service has
 * to evaluate daily limits itself because Flutter is not running while the
 * user is inside another app. Keep the two in sync.
 */
data class AppLimitRule(val pkg: String, val name: String, val limitSec: Long)

data class SessionRule(val endsAtMs: Long, val apps: Map<String, String>)

data class Snapshot(
    val dailyEnabled: Boolean = false,
    val globalLimitSec: Long? = null,
    val appLimits: List<AppLimitRule> = emptyList(),
    val breaksUntilMs: Map<String, Long> = emptyMap(),
    val session: SessionRule? = null,
) {
    /** True if anything could block at [nowMs], i.e. the service is worth running. */
    fun hasActiveRules(nowMs: Long): Boolean {
        val sessionActive = session != null && session.endsAtMs > nowMs
        val dailyActive = dailyEnabled &&
            ((globalLimitSec ?: 0L) > 0L || appLimits.any { it.limitSec > 0L })
        return sessionActive || dailyActive
    }

    companion object {
        val EMPTY = Snapshot()
    }
}

/** Declaration order matters: later entries win a tie on expiry. */
enum class Reason { DAILY_APP, DAILY_TOTAL, SESSION }

data class Decision(
    val reason: Reason,
    val pkg: String,
    val appName: String?,
    val expiresAtMs: Long,
    val usedSec: Long? = null,
    val limitSec: Long? = null,
)

object BlockPolicy {

    /**
     * @param usedSecByPkg today's foreground seconds per package (since local midnight)
     * @param nextMidnightMs when daily limits next reset, in epoch ms
     */
    fun decide(
        snapshot: Snapshot,
        pkg: String,
        usedSecByPkg: Map<String, Long>,
        nowMs: Long,
        nextMidnightMs: Long,
    ): Decision? {
        val candidates = ArrayList<Decision>(3)

        val session = snapshot.session
        if (session != null && session.endsAtMs > nowMs) {
            val name = session.apps[pkg]
            if (name != null) {
                candidates += Decision(Reason.SESSION, pkg, name, session.endsAtMs)
            }
        }

        if (snapshot.dailyEnabled) {
            val limit = snapshot.appLimits.firstOrNull { it.pkg == pkg }
            if (limit != null && limit.limitSec > 0L) {
                val used = usedSecByPkg[pkg] ?: 0L
                val breakUntil = snapshot.breaksUntilMs[pkg]
                val onBreak = breakUntil != null && breakUntil > nowMs
                if (used >= limit.limitSec && !onBreak) {
                    candidates += Decision(
                        Reason.DAILY_APP, pkg, limit.name, nextMidnightMs,
                        used, limit.limitSec,
                    )
                }
            }

            val global = snapshot.globalLimitSec
            if (global != null && global > 0L) {
                val total = usedSecByPkg.values.sum()
                if (total >= global) {
                    candidates += Decision(
                        Reason.DAILY_TOTAL, pkg, null, nextMidnightMs,
                        total, global,
                    )
                }
            }
        }

        // Stricter wins: the restriction that lasts longest; session on a tie.
        return candidates.maxWithOrNull(
            compareBy<Decision> { it.expiresAtMs }.thenBy { it.reason.ordinal }
        )
    }
}
