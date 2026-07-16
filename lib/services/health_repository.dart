import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_models.dart';

class HealthRepository {
  static final HealthRepository instance = HealthRepository._internal();
  SharedPreferences? _prefs;

  HealthRepository._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Medication ---
  List<MedicationItem> getMedications() {
    final String? jsonString = _prefs?.getString("medications");
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => MedicationItem.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveMedications(List<MedicationItem> meds) async {
    final String jsonString = jsonEncode(meds.map((e) => e.toJson()).toList());
    await _prefs?.setString("medications", jsonString);
  }

  // --- Medication Logs ---
  List<MedicationLog> getLogs(String date) {
    final String? jsonString = _prefs?.getString("med_logs_$date");
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => MedicationLog.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveLogs(String date, List<MedicationLog> logs) async {
    final String jsonString = jsonEncode(logs.map((e) => e.toJson()).toList());
    await _prefs?.setString("med_logs_$date", jsonString);
  }

  Future<void> setLog(String date, String pillId, String time, bool isTaken) async {
    final logs = getLogs(date).toList();
    final index = logs.indexWhere((it) => it.pillId == pillId && it.time == time);
    if (index != -1) {
      logs[index] = MedicationLog(date: date, pillId: pillId, time: time, isTaken: isTaken);
    } else {
      logs.add(MedicationLog(date: date, pillId: pillId, time: time, isTaken: isTaken));
    }
    await saveLogs(date, logs);
  }

  // --- Hospital Visits ---
  List<HospitalVisit> getVisits() {
    final String? jsonString = _prefs?.getString("visits");
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => HospitalVisit.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveVisits(List<HospitalVisit> visits) async {
    final String jsonString = jsonEncode(visits.map((e) => e.toJson()).toList());
    await _prefs?.setString("visits", jsonString);
  }

  // --- Pedometer (Steps) ---
  int getDefaultStepGoal() {
    return _prefs?.getInt("default_step_goal") ?? 8000;
  }

  Future<void> setDefaultStepGoal(int goal) async {
    await _prefs?.setInt("default_step_goal", goal);
  }

  StepData getStepData(String date) {
    final String? jsonString = _prefs?.getString("steps_$date");
    final int defaultGoal = getDefaultStepGoal();
    if (jsonString != null) {
      try {
        return StepData.fromJson(jsonDecode(jsonString));
      } catch (e) {
        return StepData(date: date, steps: 0, goal: defaultGoal);
      }
    } else {
      return StepData(date: date, steps: 0, goal: defaultGoal);
    }
  }

  Future<void> saveStepData(StepData data) async {
    await _prefs?.setString("steps_${data.date}", jsonEncode(data.toJson()));
  }

  int getLastSensorValue() {
    return _prefs?.getInt("last_sensor_value") ?? -1;
  }

  Future<void> saveLastSensorValue(int value) async {
    await _prefs?.setInt("last_sensor_value", value);
  }
}
