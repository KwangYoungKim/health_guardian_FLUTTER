import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_models.dart';
import 'api_service.dart';

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

    final userId = _prefs?.getString('api_user_id');
    if (userId != null) {
      final allKeys = _prefs?.getKeys() ?? {};
      final logs = <MedicationLog>[];
      for (final key in allKeys) {
        if (key.startsWith("med_logs_")) {
          final str = _prefs?.getString(key);
          if (str != null) {
            try {
              final List<dynamic> jsonList = jsonDecode(str);
              logs.addAll(jsonList.map((e) => MedicationLog.fromJson(e)));
            } catch (_) {}
          }
        }
      }
      ApiService.syncMedications(userId, meds.map((e) => e.toJson()).toList(), logs.map((e) => e.toJson()).toList())
          .catchError((e) => print("Medication sync error: $e"));
    }
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

  Map<String, List<MedicationLog>> getAllLogs() {
    final allKeys = _prefs?.getKeys() ?? {};
    final map = <String, List<MedicationLog>>{};
    for (final key in allKeys) {
      if (key.startsWith("med_logs_")) {
        final date = key.replaceFirst("med_logs_", "");
        final str = _prefs?.getString(key);
        if (str != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(str);
            map[date] = jsonList.map((e) => MedicationLog.fromJson(e)).toList();
          } catch (_) {}
        }
      }
    }
    return map;
  }

  Future<void> saveLogs(String date, List<MedicationLog> logs) async {
    final String jsonString = jsonEncode(logs.map((e) => e.toJson()).toList());
    await _prefs?.setString("med_logs_$date", jsonString);

    final userId = _prefs?.getString('api_user_id');
    if (userId != null) {
      final items = getMedications();
      final allKeys = _prefs?.getKeys() ?? {};
      final allLogs = <MedicationLog>[];
      for (final key in allKeys) {
        if (key.startsWith("med_logs_")) {
          final str = _prefs?.getString(key);
          if (str != null) {
            try {
              final List<dynamic> jsonList = jsonDecode(str);
              allLogs.addAll(jsonList.map((e) => MedicationLog.fromJson(e)));
            } catch (_) {}
          }
        }
      }
      ApiService.syncMedications(userId, items.map((e) => e.toJson()).toList(), allLogs.map((e) => e.toJson()).toList())
          .catchError((e) => print("Medication sync error: $e"));
    }
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

    final userId = _prefs?.getString('api_user_id');
    if (userId != null) {
      ApiService.syncHospitals(userId, visits.map((e) => e.toJson()).toList())
          .catchError((e) => print("Hospital sync error: $e"));
    }
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

  List<StepData> getAllSteps() {
    final allKeys = _prefs?.getKeys() ?? {};
    final steps = <StepData>[];
    for (final key in allKeys) {
      if (key.startsWith("steps_")) {
        final str = _prefs?.getString(key);
        if (str != null) {
          try {
            steps.add(StepData.fromJson(jsonDecode(str)));
          } catch (_) {}
        }
      }
    }
    return steps;
  }

  Future<void> saveStepData(StepData data) async {
    await _prefs?.setString("steps_${data.date}", jsonEncode(data.toJson()));

    final userId = _prefs?.getString('api_user_id');
    if (userId != null) {
      // Sync only this step data for simplicity
      ApiService.syncSteps(userId, [data.toJson()])
          .catchError((e) => print("Steps sync error: $e"));
    }
  }

  int getLastSensorValue() {
    return _prefs?.getInt("last_sensor_value") ?? -1;
  }

  Future<void> saveLastSensorValue(int value) async {
    await _prefs?.setInt("last_sensor_value", value);
  }

  // --- Path Tracker ---
  List<PathPoint> getDailyPath(String date) {
    final String? jsonString = _prefs?.getString("path_$date");
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => PathPoint.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveDailyPath(String date, List<PathPoint> path, {bool syncToServer = true}) async {
    final String jsonString = jsonEncode(path.map((e) => e.toJson()).toList());
    await _prefs?.setString("path_$date", jsonString);

    if (syncToServer) {
      final userId = _prefs?.getString('api_user_id');
      if (userId != null) {
        final dailyPath = DailyPath(
          id: "${userId}_$date",
          userId: userId,
          date: date,
          pathJson: jsonString,
        );
        ApiService.syncPaths(userId, [dailyPath.toJson()]).then((success) {
          if (!success) print("Auto-sync path failed for $date");
        });
      }
    }
  }

  Map<String, List<PathPoint>> getAllDailyPaths() {
    final allKeys = _prefs?.getKeys() ?? {};
    final map = <String, List<PathPoint>>{};
    for (final key in allKeys) {
      if (key.startsWith("path_")) {
        final date = key.replaceFirst("path_", "");
        final str = _prefs?.getString(key);
        if (str != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(str);
            map[date] = jsonList.map((e) => PathPoint.fromJson(e)).toList();
          } catch (_) {}
        }
      }
    }
    return map;
  }

  // --- Location Memos ---
  List<LocationMemo> getMemos(String date) {
    final String? jsonString = _prefs?.getString("location_memos_$date");
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => LocationMemo.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Map<String, List<LocationMemo>> getAllMemos() {
    final allKeys = _prefs?.getKeys() ?? {};
    final map = <String, List<LocationMemo>>{};
    for (final key in allKeys) {
      if (key.startsWith("location_memos_")) {
        final date = key.replaceFirst("location_memos_", "");
        final str = _prefs?.getString(key);
        if (str != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(str);
            map[date] = jsonList.map((e) => LocationMemo.fromJson(e)).toList();
          } catch (_) {}
        }
      }
    }
    return map;
  }

  Future<void> saveMemos(String date, List<LocationMemo> memos, {bool syncToServer = true}) async {
    final String jsonString = jsonEncode(memos.map((e) => e.toJson()).toList());
    await _prefs?.setString("location_memos_$date", jsonString);

    if (syncToServer) {
      final userId = _prefs?.getString('api_user_id');
      if (userId != null) {
        ApiService.syncMemos(userId, memos.map((e) => e.toJson()).toList()).then((success) {
          if (!success) print("Auto-sync location memos failed for $date");
        });
      }
    }
  }

  Future<void> addLocationMemo(String date, LocationMemo memo) async {
    final memos = getMemos(date);
    memos.add(memo);
    await saveMemos(date, memos);
  }

  Future<void> updateLocationMemo(String date, LocationMemo updatedMemo) async {
    final memos = getMemos(date);
    final index = memos.indexWhere((m) => m.id == updatedMemo.id);
    if (index != -1) {
      memos[index] = updatedMemo;
      await saveMemos(date, memos);
    }
  }

  Future<void> deleteLocationMemo(String date, int memoId) async {
    final memos = getMemos(date);
    memos.removeWhere((m) => m.id == memoId);
    await saveMemos(date, memos);
  }
}
