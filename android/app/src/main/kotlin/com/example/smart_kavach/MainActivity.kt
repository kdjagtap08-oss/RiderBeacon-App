package com.example.smart_kavach

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "smart_kavach/alarm"
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "playAlarm" -> {
                    try {
                        stopAlarm()

                        // Boost volume to ensure the emergency alarm is heard
                        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                        am?.let {
                            val maxVol = it.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                            val curVol = it.getStreamVolume(AudioManager.STREAM_ALARM)
                            if (curVol < (maxVol * 0.6)) {
                                it.setStreamVolume(AudioManager.STREAM_ALARM, (maxVol * 0.9).toInt(), 0)
                            }
                        }

                        val alarmUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                            ?: android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI

                        ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)?.apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                audioAttributes = AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                            } else {
                                @Suppress("DEPRECATION")
                                streamType = AudioManager.STREAM_ALARM
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                isLooping = true
                                volume = 1.0f
                            }
                            play()
                        }

                        // Trigger heavy hardware alarm vibration
                        val pattern = longArrayOf(0, 500, 200, 500, 200)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator?.vibrate(pattern, 0)
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.localizedMessage, null)
                    }
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun stopAlarm() {
        try {
            ringtone?.let {
                if (it.isPlaying) {
                    it.stop()
                }
            }
        } catch (_: Exception) {}
        ringtone = null

        try {
            vibrator?.cancel()
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
