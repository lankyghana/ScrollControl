package com.scrollcontrol.scroll_control.blocker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores enforcement after a reboot or an app update, but only if the user
 * had blocking switched on, rules are still in force and both permissions are
 * still granted. Otherwise it does nothing.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        try {
            if (!BlockerStore.isServiceWanted(context)) return
            if (!BlockerStore.loadSnapshot(context).hasActiveRules(System.currentTimeMillis())) {
                BlockerStore.setServiceWanted(context, false)
                return
            }
            if (!BlockerPermissions.ready(context)) {
                BlockerStore.setSuspendedReason(context, "permission_revoked")
                BlockerStore.setServiceWanted(context, false)
                return
            }
            BlockerService.start(context)
        } catch (e: Exception) {
            // Android may refuse a background start (e.g. after an update on
            // some OEMs). The app re-syncs the next time it is opened.
            BlockerStore.setSuspendedReason(context, "background_restricted")
        }
    }
}
