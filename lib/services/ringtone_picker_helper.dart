import 'dart:io';
import 'package:flutter/services.dart';

class RingtonePickerHelper {
  static const _channel = MethodChannel('com.example.health_guardian_flutter/ringtone_picker');

  static Future<String> pickRingtone() async {
    if (Platform.isAndroid) {
      try {
        final String? uri = await _channel.invokeMethod<String>('pickRingtone');
        return uri ?? 'default';
      } catch (e) {
        print("Ringtone picker error: $e");
        return 'default';
      }
    } else {
      // iOS doesn't support Ringtone Picker, return default
      return 'default';
    }
  }
  static Future<String> getDefaultAlarmUri() async {
    if (Platform.isAndroid) {
      try {
        final String? uri = await _channel.invokeMethod<String>('getDefaultAlarmUri');
        return uri ?? 'content://settings/system/alarm_alert';
      } catch (e) {
        return 'content://settings/system/alarm_alert';
      }
    }
    return 'default';
  }
  static Future<void> startRingtone(String uri, bool vibrate) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startRingtone', {
          'uri': uri,
          'vibrate': vibrate,
        });
      } catch (e) {
        print("Error starting ringtone: $e");
      }
    }
  }

  static Future<void> stopRingtone() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopRingtone');
      } catch (e) {
        print("Error stopping ringtone: $e");
      }
    }
  }

  static String getRingtoneDisplayName(String uri) {
    if (uri == 'default') return '벨+진동';
    if (uri == 'vibrate' || uri == '진동') return '진동';
    if (uri == 'silent' || uri == '무음') return '무음';
    if (uri == '벨+진동') return '벨+진동';
    if (uri.startsWith('content://') || uri == '벨' || uri == 'pick_custom') {
      return '벨';
    }
    return '벨';
  }
}
