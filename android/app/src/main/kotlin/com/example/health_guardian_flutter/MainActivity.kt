package com.example.health_guardian_flutter

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.example.health_guardian_flutter/ringtone_picker"
    private var pendingResult: MethodChannel.Result? = null
    private val RINGTONE_PICKER_REQUEST_CODE = 999
    private val ACTIVITY_RECOGNITION_REQUEST_CODE = 1001

    private var currentRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickRingtone" -> {
                    pendingResult = result
                    openRingtonePicker()
                }
                "getDefaultAlarmUri" -> {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    result.success(uri?.toString() ?: "")
                }
                "getTimeZoneName" -> {
                    result.success(java.util.TimeZone.getDefault().id)
                }
                "startRingtone" -> {
                    val uriStr = call.argument<String>("uri")
                    val vibrate = call.argument<Boolean>("vibrate") ?: true
                    startNativeRingtoneAndVibration(uriStr, vibrate)
                    result.success(true)
                }
                "stopRingtone" -> {
                    stopNativeRingtoneAndVibration()
                    result.success(true)
                }
                "requestActivityRecognition" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if (checkSelfPermission(android.Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
                            pendingResult = result
                            requestPermissions(arrayOf(android.Manifest.permission.ACTIVITY_RECOGNITION), ACTIVITY_RECOGNITION_REQUEST_CODE)
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "scheduleAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "알람"
                    val body = call.argument<String>("body") ?: ""
                    val triggerTimeMillis = call.argument<Long>("triggerTimeMillis") ?: 0L
                    val ringtoneUri = call.argument<String>("ringtoneUri") ?: "default"
                    val vibrate = call.argument<Boolean>("vibrate") ?: true
                    val isDaily = call.argument<Boolean>("isDaily") ?: false

                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(applicationContext, AlarmReceiver::class.java).apply {
                        putExtra("ALARM_ID", id)
                        putExtra("TITLE", title)
                        putExtra("BODY", body)
                        putExtra("RINGTONE_URI", ringtoneUri)
                        putExtra("VIBRATE", vibrate)
                        putExtra("IS_DAILY", isDaily)
                        putExtra("TRIGGER_TIME", triggerTimeMillis)
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        applicationContext,
                        id,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (alarmManager.canScheduleExactAlarms()) {
                                alarmManager.setExactAndAllowWhileIdle(
                                    AlarmManager.RTC_WAKEUP,
                                    triggerTimeMillis,
                                    pendingIntent
                                )
                            } else {
                                alarmManager.setAndAllowWhileIdle(
                                    AlarmManager.RTC_WAKEUP,
                                    triggerTimeMillis,
                                    pendingIntent
                                )
                            }
                        } else {
                            alarmManager.setExactAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP,
                                triggerTimeMillis,
                                pendingIntent
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        e.printStackTrace()
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }
                "cancelAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    
                    if (id == -1) {
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancelAll()
                    } else {
                        val intent = Intent(applicationContext, AlarmReceiver::class.java)
                        val pendingIntent = PendingIntent.getBroadcast(
                            applicationContext,
                            id,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        alarmManager.cancel(pendingIntent)

                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(id)
                    }

                    val serviceIntent = Intent(applicationContext, AlarmSoundService::class.java).apply {
                        action = "STOP_SOUND"
                    }
                    try {
                        startService(serviceIntent)
                    } catch (e: Exception) {
                        // Ignore context restrictions for starting service
                    }

                    result.success(true)
                }
                "saveImageToGallery" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val file = java.io.File(filePath)
                    if (file.exists()) {
                        try {
                            val resolver = contentResolver
                            val values = android.content.ContentValues().apply {
                                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "MemoImage_" + System.currentTimeMillis() + ".jpg")
                                put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, android.os.Environment.DIRECTORY_PICTURES)
                                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                                }
                            }
                            val uri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            if (uri != null) {
                                resolver.openOutputStream(uri).use { outputStream ->
                                    java.io.FileInputStream(file).use { inputStream ->
                                        inputStream.copyTo(outputStream!!)
                                    }
                                }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    values.clear()
                                    values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                                    resolver.update(uri, values, null, null)
                                }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            e.printStackTrace()
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    } else {
                        result.error("FILE_NOT_FOUND", "File does not exist", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun openRingtonePicker() {
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
        }
        startActivityForResult(intent, RINGTONE_PICKER_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RINGTONE_PICKER_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                pendingResult?.success(uri?.toString() ?: "default")
            } else {
                pendingResult?.success("default")
            }
            pendingResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ACTIVITY_RECOGNITION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingResult?.success(granted)
            pendingResult = null
        }
    }

    private fun startNativeRingtoneAndVibration(uriStr: String?, vibrate: Boolean) {
        stopNativeRingtoneAndVibration()

        val context = applicationContext
        val uri = if (!uriStr.isNullOrEmpty() && uriStr != "default" && uriStr != "vibrate" && uriStr != "silent") {
            Uri.parse(uriStr)
        } else {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        }

        if (uriStr != "vibrate" && uriStr != "silent") {
            try {
                val ringtone = RingtoneManager.getRingtone(context, uri)
                if (ringtone != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        val aa = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                        ringtone.audioAttributes = aa
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        ringtone.isLooping = true
                    }
                    ringtone.play()
                    currentRingtone = ringtone
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        if (vibrate && uriStr != "silent") {
            try {
                val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                    vibratorManager.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                
                vibrator = vib
                val pattern = longArrayOf(0, 1000, 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(pattern, 0)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun stopNativeRingtoneAndVibration() {
        try {
            currentRingtone?.stop()
            currentRingtone = null
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
