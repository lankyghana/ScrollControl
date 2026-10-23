package com.scrollcontrol.scroll_control.blocker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import com.scrollcontrol.scroll_control.MainActivity
import com.scrollcontrol.scroll_control.R
import java.util.Calendar

/**
 * Foreground service that enforces the user's restrictions.
 *
 * One instance only (Android never runs two of the same service). It polls
 * usage events about once a second, and only while the screen is on and
 * something could actually block; otherwise it stops itself. It stops
 * immediately when Usage Access or "Display over other apps" is revoked.
 */
class BlockerService : Service() {

    private lateinit var worker: HandlerThread
    private lateinit var bg: Handler
    private val main = Handler(Looper.getMainLooper())

    private lateinit var tracker: UsageTracker
    private lateinit var overlay: BlockOverlay

    @Volatile private var snapshot: Snapshot = Snapshot.EMPTY
    @Volatile private var exempt: Set<String> = emptySet()
    private var exemptComputedAt = 0L
    @Volatile private var alive = false
    @Volatile private var screenOn = true

    private val tickRunnable = Runnable { tick() }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    bg.removeCallbacks(tickRunnable)
                    main.post { overlay.hide() }
                }
                Intent.ACTION_SCREEN_ON -> {
                    screenOn = true
                    scheduleTick(0L)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        worker = HandlerThread("scrollcontrol-blocker").apply { start() }
        bg = Handler(worker.looper)
        tracker = UsageTracker(getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager)
        overlay = BlockOverlay(this, ::goHome, ::openManage)
        screenOn = (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            },
        )
        alive = true
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must go foreground promptly after startForegroundService().
        try {
            startAsForeground()
        } catch (e: Exception) {
            BlockerStore.setSuspendedReason(this, "foreground_start_failed")
            shutDown(clearWanted = false)
            return START_NOT_STICKY
        }

        // A restart that races a self-shutdown revives the service.
        alive = true

        // Every (re)start picks up the rules Dart just saved.
        bg.post {
            snapshot = BlockerStore.loadSnapshot(this)
            BlockerStore.setSuspendedReason(this, null)
            scheduleTick(0L)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        alive = false
        running = false
        bg.removeCallbacksAndMessages(null)
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        main.post { overlay.hide() }
        worker.quitSafely()
        super.onDestroy()
    }

    // ── Polling ──────────────────────────────────────────────────────────────

    private fun scheduleTick(delayMs: Long) {
        if (!alive || !screenOn) return
        bg.removeCallbacks(tickRunnable)
        bg.postDelayed(tickRunnable, delayMs)
    }

    private fun tick() {
        if (!alive) return
        val now = System.currentTimeMillis()

        if (!BlockerPermissions.ready(this)) {
            // Revoked while running: stop enforcing immediately and say why.
            BlockerStore.setSuspendedReason(this, "permission_revoked")
            notifySuspended()
            shutDown(clearWanted = true)
            return
        }

        val snap = snapshot
        if (!snap.hasActiveRules(now)) {
            // Session over and no daily rules: nothing left to enforce.
            shutDown(clearWanted = true)
            return
        }

        if (now - exemptComputedAt > EXEMPT_REFRESH_MS) {
            exempt = ExemptApps.compute(this)
            exemptComputedAt = now
        }

        val dayStart = startOfDay(now)
        tracker.refresh(now, dayStart)

        val fg = tracker.foreground
        val decision = if (fg == null || fg in exempt) {
            null
        } else {
            BlockPolicy.decide(
                snap, fg, tracker.usedSecondsByPackage(now), now, nextDay(dayStart),
            )
        }

        if (decision != null) {
            val name = decision.appName?.takeIf { it.isNotBlank() } ?: label(decision.pkg)
            main.post { if (alive) overlay.show(decision, name) }
        } else {
            main.post { overlay.hide() }
        }

        scheduleTick(POLL_MS)
    }

    // ── Overlay actions (main thread) ────────────────────────────────────────

    private fun goHome() {
        overlay.hide()
        try {
            startActivity(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }

    private fun openManage() {
        overlay.hide()
        BlockerStore.setPendingRoute(this, "/focus")
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        } catch (_: Exception) {
        }
    }

    // ── Lifecycle helpers ────────────────────────────────────────────────────

    private fun shutDown(clearWanted: Boolean) {
        if (clearWanted) BlockerStore.setServiceWanted(this, false)
        alive = false
        main.post {
            overlay.hide()
            if (!alive) {
                stopForeground(true)
                stopSelf()
            }
        }
    }

    private fun label(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        pkg
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ACTIVE, "App blocking", NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while ScrollControl is enforcing your limits."
                    setShowBadge(false)
                },
            )
        }

        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ACTIVE)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("ScrollControl is enforcing your limits")
            .setContentText("Restricted apps are blocked. Tap to manage.")
            .setContentIntent(open)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun notifySuspended() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ALERT, "Blocking paused", NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ALERT)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        try {
            nm.notify(
                NOTIF_ID_ALERT,
                builder.setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle("App blocking turned off")
                    .setContentText("A permission was removed. Open ScrollControl to turn blocking back on.")
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: Exception) {
            // Notifications may be disabled; the in-app status still explains.
        }
    }

    // ── Time helpers (device local calendar day) ─────────────────────────────

    private fun startOfDay(nowMs: Long): Long = Calendar.getInstance().apply {
        timeInMillis = nowMs
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun nextDay(dayStartMs: Long): Long = Calendar.getInstance().apply {
        timeInMillis = dayStartMs
        add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    companion object {
        private const val CHANNEL_ACTIVE = "scroll_control_blocking"
        private const val CHANNEL_ALERT = "scroll_control_blocking_alert"
        private const val NOTIF_ID = 2001
        private const val NOTIF_ID_ALERT = 2002
        private const val POLL_MS = 1000L
        private const val EXEMPT_REFRESH_MS = 5L * 60 * 1000

        @Volatile
        var running = false
            private set

        /** Starts the service. Throws IllegalStateException if Android forbids it right now. */
        fun start(ctx: Context) {
            val intent = Intent(ctx, BlockerService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(intent) else ctx.startService(intent)
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, BlockerService::class.java))
        }
    }
}
