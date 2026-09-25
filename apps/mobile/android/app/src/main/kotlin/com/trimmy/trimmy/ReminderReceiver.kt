package com.trimmy.trimmy

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.time.DayOfWeek
import java.time.ZonedDateTime

/** Generic opt-in check-ins only: no account data or transaction notifications. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preference = ReminderSchedule.preference(context)
        if (intent.action == ReminderSchedule.DELIVER && preference != "off") {
            ReminderSchedule.deliver(context)
        }
        ReminderSchedule.replace(context, preference)
    }
}

object ReminderSchedule {
    const val DELIVER = "com.trimmy.trimmy.REMIND_CHECK_IN"
    const val OPEN_CAREER = "trimmy.open_career"
    private const val CHANNEL = "trimmy_check_in"
    private const val REQUEST = 7402
    private const val STORE = "trimmy_reminder"

    private fun preferences(context: Context) =
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE)

    fun preference(context: Context): String =
        preferences(context).getString("frequency", "off") ?: "off"

    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() &&
            manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun nextTime(preference: String, now: ZonedDateTime): ZonedDateTime {
        require(preference == "daily" || preference == "occasional")
        var next = now.withHour(19).withMinute(0).withSecond(0).withNano(0)
        if (!next.isAfter(now)) next = next.plusDays(1)
        if (preference == "occasional") {
            while (next.dayOfWeek !in setOf(DayOfWeek.MONDAY, DayOfWeek.WEDNESDAY, DayOfWeek.FRIDAY)) {
                next = next.plusDays(1)
            }
        }
        return next
    }

    fun replace(context: Context, preference: String): Boolean {
        require(preference in setOf("daily", "occasional", "off"))
        val alarm = context.getSystemService(AlarmManager::class.java)
        val delivery = PendingIntent.getBroadcast(
            context, REQUEST,
            Intent(context, ReminderReceiver::class.java).setAction(DELIVER),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm.cancel(delivery)
        if (!preferences(context).edit().putString("frequency", preference).commit()) return false
        if (preference == "off") {
            context.getSystemService(NotificationManager::class.java).cancel(REQUEST)
            return true
        }
        if (!allowed(context)) return false
        val next = nextTime(preference, ZonedDateTime.now()).toInstant().toEpochMilli()
        // A check-in is not an alarm clock. Let Android batch it for battery life.
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, delivery)
        return true
    }

    fun deliver(context: Context) {
        if (!allowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Daily check-in", NotificationManager.IMPORTANCE_DEFAULT),
        )
        val open = PendingIntent.getActivity(
            context, REQUEST,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(OPEN_CAREER, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_trimmy)
            .setContentTitle("Your desk is waiting")
            .setContentText("Clock in for today's Trimmy challenge.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        try { manager.notify(REQUEST, notification) } catch (_: SecurityException) { }
    }

    fun recordOpen(context: Context) {
        preferences(context).edit().putBoolean("open_career", true).commit()
    }

    fun consumeOpen(context: Context): Boolean {
        val pending = preferences(context).getBoolean("open_career", false)
        preferences(context).edit().remove("open_career").commit()
        return pending
    }
}
