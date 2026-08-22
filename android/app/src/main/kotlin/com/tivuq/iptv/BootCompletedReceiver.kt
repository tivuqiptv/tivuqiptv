package com.tivuq.iptv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val preferences = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        if (!preferences.getBoolean("flutter.autoStartOnBoot", false)) return

        AutoLaunchService.configure(context, true)

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        runCatching { context.startActivity(launchIntent) }
    }
}
