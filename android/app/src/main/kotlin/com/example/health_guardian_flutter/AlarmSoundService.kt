package com.example.health_guardian_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service(), SensorEventListener {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var playCount = 0
    private val MAX_PLAY_COUNT = 5
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }

    private val NOTIFICATION_ID = 1009
    private var startTimeMillis = 0L

    // Sensors
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var proximity: Sensor? = null

    // Interaction Receiver
    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            Log.d("AlarmSoundService", "Action received: $action")
            
            // Prevent immediate triggering right after start
            if (System.currentTimeMillis() - startTimeMillis < 2000) {
                return
            }

            if (action == Intent.ACTION_SCREEN_ON || 
                action == Intent.ACTION_USER_PRESENT || 
                action == "android.media.VOLUME_CHANGED_ACTION") {
                Log.d("AlarmSoundService", "Stopping sound due to user interaction: $action")
                stopSelf()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d("AlarmSoundService", "onCreate")
        startTimeMillis = System.currentTimeMillis()

        // Register receivers for screen states and physical volume changes
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction("android.media.VOLUME_CHANGED_ACTION")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
        }

        // Register sensors
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager?.let { sm ->
            accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            proximity = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)

            accelerometer?.let { sensor ->
                sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            }
            proximity?.let { sensor ->
                sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_SOUND") {
            Log.d("AlarmSoundService", "Stopping sound via intent action")
            stopSelf()
            return START_NOT_STICKY
        }

        startTimeMillis = System.currentTimeMillis()
        showForegroundNotification()

        mediaPlayer?.release()
        vibrator?.cancel()
        handler.removeCallbacks(stopRunnable)
        playCount = 0

        val ringtoneUriStr = intent?.getStringExtra("RINGTONE_URI")
        val vibrate = intent?.getBooleanExtra("VIBRATE", true) ?: true

        Log.d("AlarmSoundService", "Playing sound: $ringtoneUriStr, vibrate: $vibrate")

        val uri = if (!ringtoneUriStr.isNullOrEmpty() && ringtoneUriStr != "default" && ringtoneUriStr != "vibrate" && ringtoneUriStr != "silent") {
            Uri.parse(ringtoneUriStr)
        } else {
            android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
        }

        if (ringtoneUriStr != "vibrate" && ringtoneUriStr != "silent") {
            try {
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(applicationContext, uri)
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    isLooping = false
                    
                    setOnCompletionListener {
                        playCount++
                        if (playCount < MAX_PLAY_COUNT) {
                            it.start()
                        } else {
                            stopSelf()
                        }
                    }
                    prepare()
                    start()
                }

                val duration = mediaPlayer?.duration ?: 5000
                val timeout = (duration * MAX_PLAY_COUNT).toLong() + 2000L
                val finalTimeout = if (timeout > 60000L || timeout <= 0) 60000L else timeout
                handler.postDelayed(stopRunnable, finalTimeout)

            } catch (e: Exception) {
                Log.e("AlarmSoundService", "MediaPlayer error", e)
            }
        } else {
            handler.postDelayed(stopRunnable, 60000L)
        }

        if (vibrate && ringtoneUriStr != "silent") {
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
                Log.e("AlarmSoundService", "Vibration error", e)
            }
        }

        return START_NOT_STICKY
    }

    private fun showForegroundNotification() {
        val channelId = "native_alarm_service_channel"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Alarm Player Service",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
        }

        val stopSelfIntent = Intent(this, AlarmSoundService::class.java).apply {
            action = "STOP_SOUND"
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            stopSelfIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("알람이 울리는 중입니다")
            .setContentText("알람을 끄려면 아래 버튼을 누르거나, 볼륨버튼을 클릭, 폰을 흔들거나 뒤집어보세요.")
            .setSmallIcon(resources.getIdentifier("ic_launcher", "mipmap", packageName))
            .addAction(android.R.drawable.ic_media_pause, "알람 끄기", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                notification, 
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // SensorEventListener Overrides
    override fun onSensorChanged(event: SensorEvent) {
        val type = event.sensor.type
        
        // Prevent immediate triggering right after start
        if (System.currentTimeMillis() - startTimeMillis < 2000) {
            return
        }

        if (type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]

            // 1. Shake Detection (Slightly more sensitive threshold: 2.2)
            val gForce = Math.sqrt((x * x + y * y + z * z).toDouble()) / SensorManager.GRAVITY_EARTH
            if (gForce > 2.2) {
                Log.d("AlarmSoundService", "Stopping sound due to shake: gForce=$gForce")
                stopSelf()
                return
            }

            // 2. Flip Detection (Face down - slightly more tolerant thresholds)
            if (z < -7.5 && Math.abs(x) < 3.0 && Math.abs(y) < 3.0) {
                Log.d("AlarmSoundService", "Stopping sound due to flip (face down)")
                stopSelf()
                return
            }
        } else if (type == Sensor.TYPE_PROXIMITY) {
            val distance = event.values[0]
            val maxRange = event.sensor.maximumRange
            if (distance < maxRange && distance < 4.0) {
                Log.d("AlarmSoundService", "Stopping sound due to proximity sensor detection")
                stopSelf()
                return
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not used
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("AlarmSoundService", "onDestroy")
        
        try {
            unregisterReceiver(actionReceiver)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            sensorManager?.unregisterListener(this)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        handler.removeCallbacks(stopRunnable)
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (e: Exception) {
            // ignore
        }
        mediaPlayer = null

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            // ignore
        }
        vibrator = null
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
