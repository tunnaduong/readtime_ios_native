package com.fatties.readtime.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.fatties.readtime.R
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * The daily reading reminder. Android has no repeating "every Tuesday at 20:00" notification,
 * so each reminder schedules the next one when it fires, and the app tops the schedule up on
 * every launch in case the work was dropped (Doze, force stop, reboot).
 */
object ReminderManager {
    const val CHANNEL_ID = "reading-reminder"
    private const val WORK_NAME = "readtime.daily-reminder"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_WEEKDAYS = "weekdays"

    fun schedule(context: Context, time: AppleDate, weekdays: List<Int>) {
        val local = LocalDateTime.ofInstant(time.instant, ZoneId.systemDefault())
        schedule(context, local.hour, local.minute, weekdays)
    }

    fun schedule(context: Context, hour: Int, minute: Int, weekdays: List<Int>) {
        val days = weekdays.ifEmpty { (1..7).toList() }
        val next = nextOccurrence(hour, minute, days) ?: return
        val delay = Duration.between(LocalDateTime.now(), next)
        val request = OneTimeWorkRequestBuilder<ReminderWorker>()
            .setInitialDelay(maxOf(0, delay.toMillis()), TimeUnit.MILLISECONDS)
            .setInputData(
                workDataOf(
                    KEY_HOUR to hour,
                    KEY_MINUTE to minute,
                    KEY_WEEKDAYS to days.toIntArray(),
                )
            )
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    private fun nextOccurrence(hour: Int, minute: Int, weekdays: List<Int>): LocalDateTime? {
        val now = LocalDateTime.now()
        for (offset in 0..7L) {
            val day: LocalDate = now.toLocalDate().plusDays(offset)
            if (!weekdays.contains(day.iosWeekday)) continue
            val candidate = day.atTime(hour, minute)
            if (candidate.isAfter(now)) return candidate
        }
        return null
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.reminder_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.reminder_channel_description)
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    class ReminderWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
        override fun doWork(): Result {
            val hour = inputData.getInt(KEY_HOUR, 20)
            val minute = inputData.getInt(KEY_MINUTE, 0)
            val weekdays = inputData.getIntArray(KEY_WEEKDAYS)?.toList() ?: (1..7).toList()

            post(applicationContext)
            // Queue the next one; a reminder that fires is always followed by another.
            schedule(applicationContext, hour, minute, weekdays)
            return Result.success()
        }

        private fun post(context: Context) {
            val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            if (!allowed) return

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.reminder_title))
                .setContentText(context.getString(R.string.reminder_body))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(1, notification)
        }
    }
}
