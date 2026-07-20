// lib/services/alarm_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AlarmItem {
  final int id;
  final int intervalMinutes;
  final int nextTriggerTimeMillis;
  final String title;
  final String ringtoneUri;
  final bool skipNext;
  final bool isRunning;
  final int remainingTimeMillis;

  AlarmItem({
    required this.id,
    required this.intervalMinutes,
    required this.nextTriggerTimeMillis,
    this.title = "",
    this.ringtoneUri = "",
    this.skipNext = false,
    this.isRunning = true,
    this.remainingTimeMillis = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'intervalMinutes': intervalMinutes,
    'nextTriggerTimeMillis': nextTriggerTimeMillis,
    'title': title,
    'ringtoneUri': ringtoneUri,
    'skipNext': skipNext,
    'isRunning': isRunning,
    'remainingTimeMillis': remainingTimeMillis,
  };

  factory AlarmItem.fromJson(Map<String, dynamic> json) => AlarmItem(
    id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] as int? ?? 0),
    intervalMinutes: json['intervalMinutes'] is String ? int.tryParse(json['intervalMinutes']) ?? 0 : (json['intervalMinutes'] as int? ?? 0),
    nextTriggerTimeMillis: json['nextTriggerTimeMillis'] is String ? int.tryParse(json['nextTriggerTimeMillis']) ?? 0 : (json['nextTriggerTimeMillis'] as int? ?? 0),
    title: json['title'] as String? ?? "",
    ringtoneUri: json['ringtoneUri'] as String? ?? "",
    skipNext: json['skipNext'] as bool? ?? false,
    isRunning: json['isRunning'] as bool? ?? true,
    remainingTimeMillis: json['remainingTimeMillis'] is String ? int.tryParse(json['remainingTimeMillis']) ?? 0 : (json['remainingTimeMillis'] as int? ?? 0),
  );

  AlarmItem copyWith({
    int? id,
    int? intervalMinutes,
    int? nextTriggerTimeMillis,
    String? title,
    String? ringtoneUri,
    bool? skipNext,
    bool? isRunning,
    int? remainingTimeMillis,
  }) {
    return AlarmItem(
      id: id ?? this.id,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      nextTriggerTimeMillis: nextTriggerTimeMillis ?? this.nextTriggerTimeMillis,
      title: title ?? this.title,
      ringtoneUri: ringtoneUri ?? this.ringtoneUri,
      skipNext: skipNext ?? this.skipNext,
      isRunning: isRunning ?? this.isRunning,
      remainingTimeMillis: remainingTimeMillis ?? this.remainingTimeMillis,
    );
  }
}

class AlarmRepository {
  static const String _key = "alarms_json";

  Future<List<AlarmItem>> getAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key) ?? "[]";
    try {
      final List<dynamic> array = jsonDecode(jsonString);
      return array.map((e) => AlarmItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAlarms(List<AlarmItem> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(alarms.map((e) => e.toJson()).toList());
    await prefs.setString(_key, jsonString);

    // Sync to backend if logged in
    final userId = prefs.getString('api_user_id');
    if (userId != null) {
      ApiService.syncAlarms(userId, alarms.map((e) => e.toJson()).toList())
          .catchError((e) => print("Alarm sync error: $e"));
    }
  }

  Future<void> addAlarm(AlarmItem alarm) async {
    final alarms = await getAlarms();
    alarms.add(alarm);
    await saveAlarms(alarms);
  }

  Future<void> removeAlarm(int id) async {
    final alarms = await getAlarms();
    alarms.removeWhere((it) => it.id == id);
    await saveAlarms(alarms);
  }

  Future<void> updateAlarm(AlarmItem alarm) async {
    final alarms = await getAlarms();
    final index = alarms.indexWhere((it) => it.id == alarm.id);
    if (index != -1) {
      alarms[index] = alarm;
      await saveAlarms(alarms);
    }
  }
}
