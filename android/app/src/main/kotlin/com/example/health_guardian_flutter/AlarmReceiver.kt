package com.example.health_guardian_flutter

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("ALARM_ID", -1)
        if (alarmId == -1) return

        val title = intent.getStringExtra("TITLE") ?: "알람"
        val body = intent.getStringExtra("BODY") ?: "알람 시간이 되었습니다."
        val ringtoneUri = intent.getStringExtra("RINGTONE_URI") ?: "default"
        val vibrate = intent.getBooleanExtra("VIBRATE", true)
        val isDaily = intent.getBooleanExtra("IS_DAILY", false)
        val triggerTimeMillis = intent.getLongExtra("TRIGGER_TIME", 0L)

        Log.d("AlarmReceiver", "Alarm triggered: id=$alarmId, title=$title, isDaily=$isDaily")

        showNotification(context, alarmId, title, body, ringtoneUri)

        // Start playing alarm sound
        val serviceIntent = Intent(context, AlarmSoundService::class.java).apply {
            putExtra("RINGTONE_URI", ringtoneUri)
            putExtra("VIBRATE", vibrate)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // Reschedule if daily
        if (isDaily && triggerTimeMillis > 0L) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val nextIntent = Intent(context, AlarmReceiver::class.java).apply {
                putExtras(intent)
                putExtra("TRIGGER_TIME", triggerTimeMillis + 24 * 60 * 60 * 1000L)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                alarmId,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTimeMillis + 24 * 60 * 60 * 1000L,
                            pendingIntent
                        )
                    } else {
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTimeMillis + 24 * 60 * 60 * 1000L,
                            pendingIntent
                        )
                    }
                } else {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTimeMillis + 24 * 60 * 60 * 1000L,
                        pendingIntent
                    )
                }
            } catch (e: Exception) {
                Log.e("AlarmReceiver", "Failed to reschedule alarm", e)
            }
        }
    }

    private fun showNotification(context: Context, alarmId: Int, title: String, body: String, ringtoneUri: String) {
        val channelId = "native_alarm_channel"
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Native Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Channel for native alarm background play"
                enableVibration(true)
                setSound(null, null) // Sound is played by service
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(context, AlarmSoundService::class.java).apply {
            action = "STOP_SOUND"
        }
        val stopPendingIntent = PendingIntent.getService(
            context,
            alarmId,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName))
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(stopPendingIntent)
            .setAutoCancel(true)
            .addAction(android.R.drawable.ic_media_pause, "알람 끄기", stopPendingIntent)

        notificationManager.notify(alarmId, builder.build())
    }
}
