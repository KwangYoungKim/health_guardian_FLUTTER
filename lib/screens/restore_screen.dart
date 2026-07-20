import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/alarm_repository.dart';
import '../services/memo_storage.dart';
import '../services/health_repository.dart';
import '../models/health_models.dart';

class RestoreScreen extends StatefulWidget {
  @override
  _RestoreScreenState createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _nicknameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _handleSync() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '로그인 중...';
    });

    try {
      final nickname = _nicknameController.text.trim();
      final pin = _pinController.text.trim();
      final user = await ApiService.login(nickname, pin);
      if (user == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = '로그인 실패: 닉네임 또는 PIN을 확인하세요.';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final currentNickname = prefs.getString('api_nickname');
      final isUserSwitch = currentNickname != null && currentNickname != nickname;

      if (isUserSwitch) {
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
      }

      await prefs.setString('api_user_id', user.id);
      await prefs.setString('api_nickname', user.nickname);
      await prefs.setString('api_pin', user.pin);

      setState(() {
        _statusMessage = '데이터 동기화(병합) 중...';
      });

      // 1. Alarms
      final serverAlarmsJson = await ApiService.getAlarms(user.id);
      final serverAlarms = serverAlarmsJson.map((e) => AlarmItem.fromJson(e)).toList();
      final localAlarms = await AlarmRepository().getAlarms();
      
      final Map<int, AlarmItem> mergedAlarms = {};
      for (var a in serverAlarms) mergedAlarms[a.id] = a;
      for (var a in localAlarms) mergedAlarms[a.id] = a;
      
      final finalAlarms = mergedAlarms.values.toList();
      await AlarmRepository().saveAlarms(finalAlarms);
      await ApiService.syncAlarms(user.id, finalAlarms.map((e) => e.toJson()).toList());

      // 2. Memos
      final serverMemosJson = await ApiService.getRichMemos(user.id);
      final serverMemos = serverMemosJson.map((e) => RichMemo.fromJson(e)).toList();
      final localMemos = await MemoStorage().getAllMemos();
      
      final Map<String, RichMemo> mergedMemos = {};
      for (var m in serverMemos) mergedMemos[m.id] = m;
      for (var m in localMemos) {
        if (mergedMemos.containsKey(m.id)) {
          if (m.lastModified > mergedMemos[m.id]!.lastModified) {
            mergedMemos[m.id] = m;
          }
        } else {
          mergedMemos[m.id] = m;
        }
      }
      final finalMemos = mergedMemos.values.toList();
      await MemoStorage().saveAllMemos(finalMemos);
      await ApiService.syncRichMemos(user.id, finalMemos.map((e) => e.toJson()).toList());

      // Download images from server for memos (fix "image not found" on new device)
      setState(() { _statusMessage = '이미지 다운로드 중...'; });
      try {
        final directory = await getApplicationDocumentsDirectory();
        final imageDir = Directory('${directory.path}/memo_images');
        if (!await imageDir.exists()) {
          await imageDir.create(recursive: true);
        }
        for (int i = 0; i < finalMemos.length; i++) {
          final memo = finalMemos[i];
          final blocks = MemoStorage.deserializeBlocks(memo.contentJson);
          bool changed = false;
          for (var block in blocks) {
            if (block.type == 'image') {
              // Extract just the filename (UUID based name like img_xxxx.jpg)
              final filename = block.content.split('/').last;
              if (filename.isEmpty) continue;
              final localFile = File('${imageDir.path}/$filename');
              // Only download if not already present locally
              if (!await localFile.exists()) {
                try {
                  final res = await http.get(
                    Uri.parse('${ApiService.baseUrl}/images/$filename'),
                  );
                  if (res.statusCode == 200) {
                    await localFile.writeAsBytes(res.bodyBytes);
                    block.content = localFile.path;
                    changed = true;
                  }
                } catch (_) {}
              } else if (block.content != localFile.path) {
                // Ensure block.content references the correct local path
                block.content = localFile.path;
                changed = true;
              }
            }
          }
          if (changed) {
            finalMemos[i] = RichMemo(
              id: memo.id,
              title: memo.title,
              contentJson: MemoStorage.serializeBlocks(blocks),
              lastModified: memo.lastModified,
              createdAt: memo.createdAt,
              pinned: memo.pinned,
            );
          }
        }
        await MemoStorage().saveAllMemos(finalMemos);
      } catch (e) {
        // Image download errors are non-fatal
      }

      // 3. Hospitals
      final serverHospitalsJson = await ApiService.getHospitals(user.id);
      final serverHospitals = serverHospitalsJson.map((e) => HospitalVisit.fromJson(e)).toList();
      final localHospitals = HealthRepository.instance.getVisits();
      
      final Map<String, HospitalVisit> mergedHospitals = {};
      for (var h in serverHospitals) mergedHospitals[h.id] = h;
      for (var h in localHospitals) mergedHospitals[h.id] = h;
      
      final finalHospitals = mergedHospitals.values.toList();
      await HealthRepository.instance.saveVisits(finalHospitals); // internally calls ApiService.syncHospitals

      // 4. Medications & Logs
      final serverMedsMap = await ApiService.getMedications(user.id);
      final serverMedItems = serverMedsMap != null ? (serverMedsMap['items'] as List).map((e) => MedicationItem.fromJson(e)).toList() : <MedicationItem>[];
      final serverMedLogs = serverMedsMap != null ? (serverMedsMap['logs'] as List).map((e) => MedicationLog.fromJson(e)).toList() : <MedicationLog>[];
      
      final localMedItems = HealthRepository.instance.getMedications();
      final localMedLogsMap = HealthRepository.instance.getAllLogs();
      final localMedLogs = localMedLogsMap.values.expand((element) => element).toList();
      
      final Map<String, MedicationItem> mergedMedItems = {};
      for (var item in serverMedItems) mergedMedItems[item.id] = item;
      for (var item in localMedItems) mergedMedItems[item.id] = item;
      final finalMedItems = mergedMedItems.values.toList();
      
      final Map<String, MedicationLog> mergedMedLogs = {};
      for (var log in serverMedLogs) mergedMedLogs["${log.date}_${log.pillId}_${log.time}"] = log;
      for (var log in localMedLogs) mergedMedLogs["${log.date}_${log.pillId}_${log.time}"] = log;
      final finalMedLogs = mergedMedLogs.values.toList();
      
      await HealthRepository.instance.saveMedications(finalMedItems);
      final logsByDate = <String, List<MedicationLog>>{};
      for (var log in finalMedLogs) {
        logsByDate.putIfAbsent(log.date, () => []).add(log);
      }
      for (var entry in logsByDate.entries) {
        await HealthRepository.instance.saveLogs(entry.key, entry.value);
      }
      await ApiService.syncMedications(user.id, finalMedItems.map((e) => e.toJson()).toList(), finalMedLogs.map((e) => e.toJson()).toList());

      // 5. Steps
      final serverStepsJson = await ApiService.getSteps(user.id);
      final serverSteps = serverStepsJson.map((e) => StepData.fromJson(e)).toList();
      final localSteps = HealthRepository.instance.getAllSteps();
      
      final Map<String, StepData> mergedSteps = {};
      for (var s in serverSteps) mergedSteps[s.date] = s;
      for (var s in localSteps) {
        if (mergedSteps.containsKey(s.date)) {
          if (s.steps > mergedSteps[s.date]!.steps) {
            mergedSteps[s.date] = s; // take max steps
          }
        } else {
          mergedSteps[s.date] = s;
        }
      }
      for (var s in mergedSteps.values) {
        await HealthRepository.instance.saveStepData(s);
      }
      await ApiService.syncSteps(user.id, mergedSteps.values.map((e) => e.toJson()).toList());

      // 6. Location Memos (Walk Map Memos)
      final localLocMemosMap = HealthRepository.instance.getAllMemos();
      final localLocMemos = localLocMemosMap.values.expand((element) => element).toList();
      
      // Upload local memos first to prevent data loss on server reset
      if (localLocMemos.isNotEmpty) {
        await ApiService.syncMemos(user.id, localLocMemos.map((e) => e.toJson()).toList());
      }
      
      final serverLocMemosJson = await ApiService.getMemos(user.id);
      final serverLocMemos = serverLocMemosJson.map((e) => LocationMemo.fromJson(e)).toList();
      
      final Map<String, LocationMemo> mergedLocMemos = {};
      for (var lm in serverLocMemos) mergedLocMemos["${lm.date}_${lm.id}"] = lm;
      for (var lm in localLocMemos) mergedLocMemos["${lm.date}_${lm.id}"] = lm;
      
      final finalLocMemos = mergedLocMemos.values.toList();
      
      final locMemosByDate = <String, List<LocationMemo>>{};
      for (var lm in finalLocMemos) {
        locMemosByDate.putIfAbsent(lm.date, () => []).add(lm);
      }
      
      for (final date in locMemosByDate.keys) {
        await HealthRepository.instance.saveMemos(date, locMemosByDate[date]!, syncToServer: false);
      }
      await ApiService.syncMemos(user.id, finalLocMemos.map((e) => e.toJson()).toList());

      // 7. Daily Paths
      final localPathsMap = HealthRepository.instance.getAllDailyPaths();
      final localPaths = localPathsMap.entries.map((entry) {
        final date = entry.key;
        final points = entry.value;
        final jsonStr = jsonEncode(points.map((e) => e.toJson()).toList());
        return DailyPath(
          id: "${user.id}_$date",
          userId: user.id,
          date: date,
          pathJson: jsonStr,
        );
      }).toList();

      // Upload local paths first to prevent data loss on server reset
      if (localPaths.isNotEmpty) {
        await ApiService.syncPaths(user.id, localPaths.map((e) => e.toJson()).toList());
      }

      final serverPathsJson = await ApiService.getPaths(user.id);
      final serverPaths = serverPathsJson.map((e) => DailyPath.fromJson(e)).toList();

      final Map<String, DailyPath> mergedPaths = {};
      for (var p in serverPaths) mergedPaths[p.date] = p;
      for (var p in localPaths) {
        if (mergedPaths.containsKey(p.date)) {
          final serverLen = mergedPaths[p.date]!.pathJson.length;
          final localLen = p.pathJson.length;
          if (localLen >= serverLen) {
            mergedPaths[p.date] = p;
          }
        } else {
          mergedPaths[p.date] = p;
        }
      }

      final finalPaths = mergedPaths.values.toList();
      
      for (var dp in finalPaths) {
        try {
          final List<dynamic> jsonList = jsonDecode(dp.pathJson);
          final points = jsonList.map((e) => PathPoint.fromJson(e)).toList();
          await HealthRepository.instance.saveDailyPath(dp.date, points, syncToServer: false);
        } catch (e) {
          print("Error restoring path on cloud restore for ${dp.date}: $e");
        }
      }

      await ApiService.syncPaths(user.id, finalPaths.map((e) => e.toJson()).toList());

      setState(() {
        _isLoading = false;
        _statusMessage = '전체 데이터 동기화 완료!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '오류 발생: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('클라우드 동기화', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.sync, size: 80, color: Color(0xFF00E5FF)),
              const SizedBox(height: 24),
              const Text(
                '백엔드 서버와 기기의 데이터를 병합하여\n완벽하게 일치시킵니다.\n(알람, 약복용, 병원, 걷기, 메모)\n* Meet 데이터는 실시간 자동 동기화됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nicknameController,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '닉네임 (Nickname)',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0x1AFFFFFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  FocusScope.of(context).unfocus();
                  if (!_isLoading) _handleSync();
                },
                decoration: InputDecoration(
                  labelText: 'PIN (4자리)',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0x1AFFFFFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF00E5FF))
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      _handleSync();
                    },
                    icon: const Icon(Icons.cloud_sync, color: Colors.white),
                    label: const Text('전체 데이터 동기화 (Sync)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF).withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: TextStyle(
                  color: _statusMessage.contains('완료') ? Colors.greenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

