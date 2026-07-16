// lib/screens/alarm_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/alarm_repository.dart';
import '../services/notification_service.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({Key? key}) : super(key: key);

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final AlarmRepository repo = AlarmRepository();
  List<AlarmItem> alarms = [];
  bool showAddAlarmCard = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _minuteController = TextEditingController();
  
  final Map<int, Timer> _activeTimers = {};

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  @override
  void dispose() {
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadAlarms() async {
    final loaded = await repo.getAlarms();
    setState(() {
      alarms = loaded;
    });
    
    // Resume timers for active alarms
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var alarm in alarms) {
      if (!_activeTimers.containsKey(alarm.id)) {
        if (alarm.nextTriggerTimeMillis > now) {
          _startTimer(alarm);
        } else if (alarm.isRunning) {
          // If past due, disable it
          final updated = alarm.copyWith(isRunning: false);
          repo.updateAlarm(updated);
        }
      }
    }
  }
  
  void _startTimer(AlarmItem alarm) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = alarm.nextTriggerTimeMillis - now;
    if (delay > 0) {
      _activeTimers[alarm.id] = Timer(Duration(milliseconds: delay), () {
        NotificationService.instance.showAlarmNotification(
          "알람: ${alarm.title.isNotEmpty ? alarm.title : '지정 알람'}", 
          "${alarm.intervalMinutes}분 알람 시간이 되었습니다!"
        );
        _activeTimers.remove(alarm.id);
        
        // Disable alarm after trigger
        final updated = alarm.copyWith(isRunning: false);
        repo.updateAlarm(updated);
        _loadAlarms();
      });
    }
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
              children: [
                const Text("다중알람", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 20, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(showAddAlarmCard ? Icons.visibility : Icons.visibility_off, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          showAddAlarmCard = !showAddAlarmCard;
                        });
                      },
                    ),
                  ],
                )
              ],
            ),
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
              child: ListView.builder(
                itemCount: alarms.length,
                itemBuilder: (context, index) {
                  final alarm = alarms[index];
                  final isPast = alarm.nextTriggerTimeMillis <= DateTime.now().millisecondsSinceEpoch;
                  final statusText = alarm.isRunning && !isPast ? "활성화" : "종료됨";
                  
                  return Card(
                    color: Colors.white12,
                    child: ListTile(
                      title: Text(alarm.title.isNotEmpty ? "[${alarm.title}] ${alarm.intervalMinutes}분 알람" : "${alarm.intervalMinutes}분 알람", style: const TextStyle(color: Colors.white)),
                      subtitle: Text("상태: $statusText", style: const TextStyle(color: Colors.white70)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          _activeTimers[alarm.id]?.cancel();
                          _activeTimers.remove(alarm.id);
                          await repo.removeAlarm(alarm.id);
                          _loadAlarms();
                        },
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
