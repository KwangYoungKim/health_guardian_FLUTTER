import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'ringtone_picker_helper.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _channel = MethodChannel('com.example.health_guardian_flutter/ringtone_picker');

  NotificationService._internal();

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    if (Platform.isAndroid) {
      try {
        final String? timeZoneName = await const MethodChannel('com.example.health_guardian_flutter/ringtone_picker')
            .invokeMethod<String>('getTimeZoneName');
        if (timeZoneName != null) {
          tz.setLocalLocation(tz.getLocation(timeZoneName));
        }
      } catch (e) {
        print("Error setting local location: $e");
      }
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    if (Platform.isAndroid) {
      try {
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (e) {
        print("Error requesting notifications permission: $e");
      }
    }

    _initialized = true;
  }

  Future<void> showAlarmNotification(String title, String body, {String ringtoneUri = 'default'}) async {
    bool playSound = ringtoneUri != 'vibrate' && ringtoneUri != 'silent';
    bool enableVibration = ringtoneUri == 'vibrate' || ringtoneUri == 'default';
    String soundUri = ringtoneUri;
    if (soundUri == 'default') {
      soundUri = await RingtonePickerHelper.getDefaultAlarmUri();
    }

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'alarm_channel_v4_${soundUri.hashCode}',
      'Alarms',
      importance: Importance.max,
      priority: Priority.high,
      playSound: playSound,
      sound: (Platform.isAndroid && playSound && soundUri.startsWith('content://'))
          ? UriAndroidNotificationSound(soundUri)
          : null,
      enableVibration: enableVibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      additionalFlags: Int32List.fromList(<int>[4]),
    );
    DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(presentSound: playSound, presentAlert: true, presentBadge: true);
    NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> scheduleDailyMedicationNotification(int id, String title, String body, String timeStr, {String ringtoneUri = 'default'}) async {
    final parts = timeStr.split(':');
    if (parts.length != 2) return;
    int hour = int.tryParse(parts[0]) ?? 0;
    int minute = int.tryParse(parts[1]) ?? 0;

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    bool playSound = ringtoneUri != 'vibrate' && ringtoneUri != 'silent';
    bool enableVibration = ringtoneUri == 'vibrate' || ringtoneUri == 'default';
    String soundUri = ringtoneUri;
    if (soundUri == 'default') {
      soundUri = await RingtonePickerHelper.getDefaultAlarmUri();
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('scheduleAlarm', {
          'id': id,
          'title': title,
          'body': body,
          'triggerTimeMillis': scheduledDate.millisecondsSinceEpoch,
          'ringtoneUri': soundUri,
          'vibrate': enableVibration,
          'isDaily': true,
        });
      } catch (e) {
        print("Error scheduling native medication alarm: $e");
      }
      return;
    }

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_channel_v4_${soundUri.hashCode}',
      'Medication Alarms',
      importance: Importance.max,
      priority: Priority.high,
      playSound: playSound,
      sound: (Platform.isAndroid && playSound && soundUri.startsWith('content://'))
          ? UriAndroidNotificationSound(soundUri)
          : null,
      enableVibration: enableVibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      additionalFlags: Int32List.fromList(<int>[4]),
    );
    DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: playSound, presentAlert: true, presentBadge: true,
    );
    NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelMedicationNotification(int id) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {'id': id});
      } catch (e) {
        print("Error cancelling native medication alarm: $e");
      }
      return;
    }
    await _flutterLocalNotificationsPlugin.cancel(id);
    await RingtonePickerHelper.stopRingtone();
  }

  Future<void> scheduleHospitalNotification(int id, String title, String body, String dateStr, String timeStr, {String ringtoneUri = 'default'}) async {
    try {
      final dateParts = dateStr.split('-');
      final timeParts = timeStr.split(':');
      if (dateParts.length != 3 || timeParts.length != 2) return;
      int year = int.tryParse(dateParts[0]) ?? 0;
      int month = int.tryParse(dateParts[1]) ?? 0;
      int day = int.tryParse(dateParts[2]) ?? 0;
      int hour = int.tryParse(timeParts[0]) ?? 0;
      int minute = int.tryParse(timeParts[1]) ?? 0;

      final scheduledDate = tz.TZDateTime(tz.local, year, month, day, hour, minute);
      final now = tz.TZDateTime.now(tz.local);
      if (scheduledDate.isBefore(now)) return;

      bool playSound = ringtoneUri != 'vibrate' && ringtoneUri != 'silent';
      bool enableVibration = ringtoneUri == 'vibrate' || ringtoneUri == 'default';
      String soundUri = ringtoneUri;
      if (soundUri == 'default') {
        soundUri = await RingtonePickerHelper.getDefaultAlarmUri();
      }

      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('scheduleAlarm', {
            'id': id,
            'title': title,
            'body': body,
            'triggerTimeMillis': scheduledDate.millisecondsSinceEpoch,
            'ringtoneUri': soundUri,
            'vibrate': enableVibration,
            'isDaily': false,
          });
        } catch (e) {
          print("Error scheduling native hospital alarm: $e");
        }
        return;
      }

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'hospital_channel_v4_${soundUri.hashCode}',
        'Hospital Alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: playSound,
        sound: (Platform.isAndroid && playSound && soundUri.startsWith('content://'))
            ? UriAndroidNotificationSound(soundUri)
            : null,
        enableVibration: enableVibration,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        additionalFlags: Int32List.fromList(<int>[4]),
      );
      DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentSound: playSound, presentAlert: true, presentBadge: true,
      );
      NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print("Error scheduling hospital notification: $e");
    }
  }

  Future<void> cancelHospitalNotification(int id) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {'id': id});
      } catch (e) {
        print("Error cancelling native hospital alarm: $e");
      }
      return;
    }
    await _flutterLocalNotificationsPlugin.cancel(id);
    await RingtonePickerHelper.stopRingtone();
  }

  Future<void> scheduleSingleAlarmNotification(int id, String title, String body, int triggerTimeMillis, {String ringtoneUri = 'default'}) async {
    try {
      final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, triggerTimeMillis);
      final now = tz.TZDateTime.now(tz.local);
      if (scheduledDate.isBefore(now)) return;

      bool playSound = ringtoneUri != 'vibrate' && ringtoneUri != 'silent';
      bool enableVibration = ringtoneUri == 'vibrate' || ringtoneUri == 'default';
      String soundUri = ringtoneUri;
      if (soundUri == 'default') {
        soundUri = await RingtonePickerHelper.getDefaultAlarmUri();
      }

      if (Platform.isAndroid) {
        try {
          await _channel.invokeMethod('scheduleAlarm', {
            'id': id,
            'title': title,
            'body': body,
            'triggerTimeMillis': triggerTimeMillis,
            'ringtoneUri': soundUri,
            'vibrate': enableVibration,
            'isDaily': false,
          });
        } catch (e) {
          print("Error scheduling native single alarm: $e");
        }
        return;
      }

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'alarm_channel_v4_${soundUri.hashCode}',
        'Alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: playSound,
        sound: (Platform.isAndroid && playSound && soundUri.startsWith('content://'))
            ? UriAndroidNotificationSound(soundUri)
            : null,
        enableVibration: enableVibration,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        additionalFlags: Int32List.fromList(<int>[4]),
      );
      DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentSound: playSound, presentAlert: true, presentBadge: true,
      );
      NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print("Error scheduling single alarm notification: $e");
    }
  }

  Future<void> cancelAlarmNotification(int id) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAlarm', {'id': id});
      } catch (e) {
        print("Error cancelling native alarm: $e");
      }
      return;
    }
    await _flutterLocalNotificationsPlugin.cancel(id);
    await RingtonePickerHelper.stopRingtone();
  }
}
