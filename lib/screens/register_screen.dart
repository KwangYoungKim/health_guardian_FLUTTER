import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/memo_storage.dart';
import '../services/alarm_repository.dart';
import '../services/health_repository.dart';
import '../models/health_models.dart';
import '../main.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nicknameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;

  Future<void> _syncNewUserSession(String userId) async {
    try {
      final serverAlarmsJson = await ApiService.getAlarms(userId);
      final serverAlarms = serverAlarmsJson.map((e) => AlarmItem.fromJson(e)).toList();
      await AlarmRepository().saveAlarms(serverAlarms);

      final serverMemosJson = await ApiService.getRichMemos(userId);
      final serverMemos = serverMemosJson.map((e) => RichMemo.fromJson(e)).toList();
      await MemoStorage().saveAllMemos(serverMemos);

      final serverHospitalsJson = await ApiService.getHospitals(userId);
      final serverHospitals = serverHospitalsJson.map((e) => HospitalVisit.fromJson(e)).toList();
      await HealthRepository.instance.saveVisits(serverHospitals);

      final serverMedsMap = await ApiService.getMedications(userId);
      if (serverMedsMap != null) {
        final serverMedItems = (serverMedsMap['items'] as List).map((e) => MedicationItem.fromJson(e)).toList();
        final serverMedLogs = (serverMedsMap['logs'] as List).map((e) => MedicationLog.fromJson(e)).toList();
        await HealthRepository.instance.saveMedications(serverMedItems);
        final logsByDate = <String, List<MedicationLog>>{};
        for (var log in serverMedLogs) {
          logsByDate.putIfAbsent(log.date, () => []).add(log);
        }
        for (var entry in logsByDate.entries) {
          await HealthRepository.instance.saveLogs(entry.key, entry.value);
        }
      }

      final serverStepsJson = await ApiService.getSteps(userId);
      final serverSteps = serverStepsJson.map((e) => StepData.fromJson(e)).toList();
      for (var s in serverSteps) {
        await HealthRepository.instance.saveStepData(s);
      }

      final serverLocMemosJson = await ApiService.getMemos(userId);
      final serverLocMemos = serverLocMemosJson.map((e) => LocationMemo.fromJson(e)).toList();
      final locMemosByDate = <String, List<LocationMemo>>{};
      for (var lm in serverLocMemos) {
        locMemosByDate.putIfAbsent(lm.date, () => []).add(lm);
      }
      for (final date in locMemosByDate.keys) {
        await HealthRepository.instance.saveMemos(date, locMemosByDate[date]!, syncToServer: false);
      }

      final serverPathsJson = await ApiService.getPaths(userId);
      final serverPaths = serverPathsJson.map((e) => DailyPath.fromJson(e)).toList();
      for (var dp in serverPaths) {
        try {
          final List<dynamic> jsonList = jsonDecode(dp.pathJson);
          final points = jsonList.map((e) => PathPoint.fromJson(e)).toList();
          await HealthRepository.instance.saveDailyPath(dp.date, points, syncToServer: false);
        } catch (e) {
          print("Error restoring path on register for ${dp.date}: $e");
        }
      }
    } catch (e) {
      print('Auto background sync on login error: $e');
    }
  }

  Future<void> _handleRegister() async {
    final nickname = _nicknameController.text.trim();
    final pin = _pinController.text.trim();

    if (nickname.isEmpty || pin.length != 4 || int.tryParse(pin) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("올바른 닉네임과 4자리 PIN을 입력해주세요.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final keysToRemove = keys.where((k) =>
        k == 'alarms_json' ||
        k.startsWith('path_') ||
        k.startsWith('location_memos_') ||
        k == 'medications' ||
        k.startsWith('med_logs_') ||
        k == 'visits' ||
        k.startsWith('steps_') ||
        k == 'last_sensor_value' ||
        k == 'default_step_goal'
      ).toList();
      for (var key in keysToRemove) {
        await prefs.remove(key);
      }
      await MemoStorage().saveAllMemos([]);

      final id = const Uuid().v4();
      final success = await ApiService.register(id, nickname, pin);
      if (success) {
        final user = await ApiService.login(nickname, pin);
        if (user != null) {
          await _syncNewUserSession(user.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("사용자 등록 및 로그인 완료!")),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainScreen()),
            );
          }
        } else {
          throw Exception("등록 후 로그인에 실패했습니다.");
        }
      } else {
        throw Exception("사용자 등록에 실패했습니다. (이미 존재하는 닉네임일 수 있습니다.)");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("에러: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    final nickname = _nicknameController.text.trim();
    final pin = _pinController.text.trim();

    if (nickname.isEmpty || pin.length != 4 || int.tryParse(pin) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("올바른 닉네임과 4자리 PIN을 입력해주세요.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final keysToRemove = keys.where((k) =>
        k == 'alarms_json' ||
        k.startsWith('path_') ||
        k.startsWith('location_memos_') ||
        k == 'medications' ||
        k.startsWith('med_logs_') ||
        k == 'visits' ||
        k.startsWith('steps_') ||
        k == 'last_sensor_value' ||
        k == 'default_step_goal'
      ).toList();
      for (var key in keysToRemove) {
        await prefs.remove(key);
      }
      await MemoStorage().saveAllMemos([]);

      final user = await ApiService.login(nickname, pin);
      if (user != null) {
        await _syncNewUserSession(user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("로그인 완료!")),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      } else {
        throw Exception("로그인에 실패했습니다. 닉네임 또는 PIN을 확인해 주세요.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("에러: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "👟 Health Guardian",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "건강 지킴이 앱에 오신 것을 환영합니다",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _nicknameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "닉네임 (Nickname)",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0x1AFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "PIN (4자리 숫자)",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0x1AFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isLoading)
                    const CircularProgressIndicator(color: Color(0xFF00E5FF))
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "새로운 사용자 등록",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _handleLogin,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00E5FF)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "기존 계정으로 로그인",
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
