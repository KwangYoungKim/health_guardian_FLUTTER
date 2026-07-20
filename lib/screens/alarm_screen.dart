// lib/screens/alarm_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/alarm_repository.dart';
import '../services/notification_service.dart';
import '../services/ringtone_picker_helper.dart';
import '../services/api_service.dart';
import 'world_clock_screen.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({Key? key}) : super(key: key);

  @override
  _AlarmScreenState createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final AlarmRepository repo = AlarmRepository();
  List<AlarmItem> alarms = [];
  bool showAddAlarmCard = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _minuteController = TextEditingController();
  
  String? _nickname;
  bool _isSyncing = false;
  final Map<int, Timer> _activeTimers = {};
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _loadAlarms();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && alarms.any((a) => a.isRunning)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _titleController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  String _getRemainingTimeText(int targetMillis) {
    final diff = targetMillis - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return "00:00:00";
    final totalSecs = diff ~/ 1000;
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    final hStr = hours.toString().padLeft(2, '0');
    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');
    return "$hStr:$mStr:$sStr";
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nickname = prefs.getString('api_nickname');
      });
    }
  }

  Future<void> _loadAlarms() async {
    final loaded = await repo.getAlarms();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    List<AlarmItem> updatedList = [];
    for (var alarm in loaded) {
      var current = alarm;
      // Catch up if past due and running
      if (current.isRunning && current.nextTriggerTimeMillis <= now) {
        final newTrigger = now + (current.intervalMinutes * 60000);
        current = current.copyWith(
          skipNext: false,
          nextTriggerTimeMillis: newTrigger,
        );
        await repo.updateAlarm(current);
      }
      updatedList.add(current);
    }

    if (mounted) {
      setState(() {
        alarms = updatedList;
      });
    }

    // Manage foreground timers and native schedules
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();

    for (var alarm in alarms) {
      if (alarm.isRunning) {
        final delay = alarm.nextTriggerTimeMillis - now;
        if (delay > 0) {
          _startTimer(alarm);
          // Also register native background alarm scheduling
          await NotificationService.instance.scheduleSingleAlarmNotification(
            alarm.id.hashCode.abs() & 0x7FFFFFFF,
            alarm.title.isNotEmpty ? "🚨 [${alarm.title}] 알람" : "🚨 알람",
            "${alarm.intervalMinutes}분 알람 시간이 되었습니다!",
            alarm.nextTriggerTimeMillis,
            ringtoneUri: alarm.ringtoneUri,
          );
        }
      } else {
        // If not running, make sure native alarm is cancelled
        await NotificationService.instance.cancelAlarmNotification(alarm.id.hashCode.abs() & 0x7FFFFFFF);
      }
    }
  }

  void _startTimer(AlarmItem alarm) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = alarm.nextTriggerTimeMillis - now;
    if (delay > 0) {
      _activeTimers[alarm.id] = Timer(Duration(milliseconds: delay), () async {
        _activeTimers.remove(alarm.id);
        
        // Trigger Ringtone & Notification
        if (alarm.skipNext) {
          // If skip next is set, skip the sound and notification for this turn
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("⏭️ [${alarm.title}] 알람이 1회 건너뛰어졌습니다."),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          await RingtonePickerHelper.startRingtone(
            alarm.ringtoneUri,
            alarm.ringtoneUri == 'default' || alarm.ringtoneUri == 'vibrate',
          );
          
          await NotificationService.instance.showAlarmNotification(
            alarm.title.isNotEmpty ? "🚨 [${alarm.title}] 알람" : "🚨 알람",
            "${alarm.intervalMinutes}분 알람 시간이 되었습니다!",
            ringtoneUri: alarm.ringtoneUri,
          );
        }

        final updated = alarm.copyWith(
          skipNext: false,
          nextTriggerTimeMillis: DateTime.now().millisecondsSinceEpoch + (alarm.intervalMinutes * 60000),
        );
        await repo.updateAlarm(updated);
        _loadAlarms();
      });
    }
  }

  Future<void> _syncAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('api_user_id');
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("로그인이 필요합니다. 설정에서 로그인해 주세요.")),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final localAlarms = await repo.getAlarms();
      if (localAlarms.isNotEmpty) {
        await ApiService.syncAlarms(userId, localAlarms.map((e) => e.toJson()).toList());
      }
      
      final serverAlarmsJson = await ApiService.getAlarms(userId);
      final serverAlarms = serverAlarmsJson.map((e) => AlarmItem.fromJson(e)).toList();

      final Map<int, AlarmItem> merged = {};
      for (var a in serverAlarms) merged[a.id] = a;
      for (var a in localAlarms) merged[a.id] = a;

      final finalAlarms = merged.values.toList();
      await repo.saveAlarms(finalAlarms);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("알람 동기화 완료!")),
        );
        _loadAlarms();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("알람 동기화 실패: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _showEditDialog(AlarmItem alarm) async {
    final tCtrl = TextEditingController(text: alarm.title);
    final mCtrl = TextEditingController(text: alarm.intervalMinutes.toString());
    String selectedRingtone = alarm.ringtoneUri;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBuilder) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
          title: const Text("알람 수정", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "알람 제목",
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: mCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "알람 주기 (분)",
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text("알람음 종류", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  subtitle: Text(
                    RingtonePickerHelper.getRingtoneDisplayName(selectedRingtone),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  onTap: () async {
                    final selected = await showDialog<String>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Text("알람음 선택", style: TextStyle(color: Colors.white)),
                        children: [
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, 'default'),
                            child: const Text("벨+진동", style: TextStyle(color: Colors.white)),
                          ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, 'vibrate'),
                            child: const Text("진동", style: TextStyle(color: Colors.white)),
                          ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, 'silent'),
                            child: const Text("무음", style: TextStyle(color: Colors.white)),
                          ),
                          const Divider(color: Colors.white24),
                          SimpleDialogOption(
                            onPressed: () async {
                              final picked = await RingtonePickerHelper.pickRingtone();
                              if (ctx.mounted) {
                                Navigator.pop(context, picked);
                              }
                            },
                            child: const Text("🎵 단말기 시스템 벨소리 선택 (벨)...", style: TextStyle(color: Color(0xFF00E5FF))),
                          ),
                        ],
                      ),
                    );
                    if (selected != null) {
                      setStateBuilder(() {
                        selectedRingtone = selected;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("취소", style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final mins = int.tryParse(mCtrl.text);
                if (mins != null && mins > 0) {
                  final updated = alarm.copyWith(
                    title: tCtrl.text,
                    intervalMinutes: mins,
                    ringtoneUri: selectedRingtone,
                    nextTriggerTimeMillis: DateTime.now().millisecondsSinceEpoch + (mins * 60000),
                  );
                  await repo.updateAlarm(updated);
                  _loadAlarms();
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("저장"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("다중알람", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 20, fontWeight: FontWeight.bold)),
                    if (_nickname != null && _nickname!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "👤 $_nickname",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                        )
                      : IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.sync, color: Color(0xFF00E5FF)),
                          onPressed: _syncAlarms,
                        ),
                    const SizedBox(width: 12),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                      onPressed: () {
                        setState(() {
                          showAddAlarmCard = !showAddAlarmCard;
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.volume_off, color: Colors.redAccent),
                      tooltip: "모든 알람 끄기",
                      onPressed: () async {
                        await RingtonePickerHelper.stopRingtone();
                        if (Platform.isAndroid) {
                          try {
                            const channel = MethodChannel('com.example.health_guardian_flutter/ringtone_picker');
                            await channel.invokeMethod('cancelAlarm', {'id': -1});
                          } catch (e) {
                            print("Error stopping all sounds: $e");
                          }
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🔇 모든 알람 벨소리와 진동이 중지되었습니다."),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.language, color: Color(0xFF00E5FF)),
                      tooltip: "세계 시계",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const WorldClockScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (showAddAlarmCard)
              Card(
                color: Colors.white12,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: "알람 제목", labelStyle: TextStyle(color: Colors.white70)),
                      ),
                      TextField(
                        controller: _minuteController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: "알람 추가 (분)", labelStyle: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final mins = int.tryParse(_minuteController.text);
                          if (mins != null && mins > 0) {
                            final alarm = AlarmItem(
                              id: DateTime.now().millisecondsSinceEpoch,
                              intervalMinutes: mins,
                              nextTriggerTimeMillis: DateTime.now().millisecondsSinceEpoch + (mins * 60000),
                              title: _titleController.text,
                              ringtoneUri: 'default',
                            );
                            await repo.addAlarm(alarm);
                            _startTimer(alarm);
                            
                            _titleController.clear();
                            _minuteController.clear();
                            setState(() {
                              showAddAlarmCard = false;
                            });
                            _loadAlarms();
                          }
                        },
                        child: const Text("알람 추가"),
                      )
                    ],
                  ),
                ),
              ),
            Expanded(
              child: alarms.isEmpty
                  ? const Center(child: Text("등록된 알람이 없습니다.", style: TextStyle(color: Colors.white70)))
                  : ListView.builder(
                      itemCount: alarms.length,
                      itemBuilder: (context, index) {
                        final alarm = alarms[index];
                        final isPast = alarm.nextTriggerTimeMillis <= DateTime.now().millisecondsSinceEpoch;
                        final remainingText = _getRemainingTimeText(alarm.nextTriggerTimeMillis);
                        final statusText = alarm.isRunning && !isPast ? remainingText : "정지됨";
                        
                        return Card(
                          color: const Color(0x1AFFFFFF),
                          child: ListTile(
                            title: Text(
                              alarm.title.isNotEmpty ? "[${alarm.title}] ${alarm.intervalMinutes}분 알람" : "${alarm.intervalMinutes}분 알람",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              "상태: $statusText\n알람 모드: ${RingtonePickerHelper.getRingtoneDisplayName(alarm.ringtoneUri)}${alarm.skipNext ? '\n(⚠️ 다음 1회 건너뛰기 예정)' : ''}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    alarm.isRunning ? Icons.pause : Icons.play_arrow,
                                    color: alarm.isRunning ? Colors.yellowAccent : Colors.greenAccent,
                                  ),
                                  tooltip: alarm.isRunning ? "일시정지" : "시작",
                                  onPressed: () async {
                                    // Optimistic UI updates
                                    setState(() {
                                      alarms[index] = alarm.copyWith(isRunning: !alarm.isRunning);
                                    });
                                    final updated = alarm.copyWith(
                                      isRunning: !alarm.isRunning,
                                      nextTriggerTimeMillis: DateTime.now().millisecondsSinceEpoch + (alarm.intervalMinutes * 60000),
                                    );
                                    await repo.updateAlarm(updated);
                                    _loadAlarms();
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next,
                                    color: alarm.skipNext ? Colors.redAccent : Colors.white70,
                                  ),
                                  tooltip: "다음 알람 1회 건너뛰기",
                                  onPressed: () async {
                                    setState(() {
                                      alarms[index] = alarm.copyWith(skipNext: !alarm.skipNext);
                                    });
                                    final updated = alarm.copyWith(skipNext: !alarm.skipNext);
                                    await repo.updateAlarm(updated);
                                    _loadAlarms();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                  onPressed: () => _showEditDialog(alarm),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () async {
                                    // Optimistic UI updates
                                    setState(() {
                                      alarms.removeAt(index);
                                    });
                                    _activeTimers[alarm.id]?.cancel();
                                    _activeTimers.remove(alarm.id);
                                    await repo.removeAlarm(alarm.id);
                                    await NotificationService.instance.cancelAlarmNotification(alarm.id.hashCode.abs() & 0x7FFFFFFF);
                                    _loadAlarms();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}
