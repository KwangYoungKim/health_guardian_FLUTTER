import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_models.dart';
import '../services/health_repository.dart';
import '../services/api_service.dart';
import '../services/ringtone_picker_helper.dart';
import '../services/notification_service.dart';

class HospitalScreen extends StatefulWidget {
  const HospitalScreen({super.key});

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  List<HospitalVisit> _visits = [];
  bool _isSyncing = false;
  String? _nickname;

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _loadData();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nickname = prefs.getString('api_nickname');
      });
    }
  }

  Future<void> _syncHospitalVisits() async {
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
      final localVisits = HealthRepository.instance.getVisits();

      if (localVisits.isNotEmpty) {
        await ApiService.syncHospitals(userId, localVisits.map((e) => e.toJson()).toList());
      }

      final serverVisitsJson = await ApiService.getHospitals(userId);
      final serverVisits = serverVisitsJson.map((e) => HospitalVisit.fromJson(e)).toList();

      final Map<String, HospitalVisit> mergedVisits = {};
      for (var v in serverVisits) mergedVisits[v.id] = v;
      for (var v in localVisits) mergedVisits[v.id] = v;

      final finalVisits = mergedVisits.values.toList();
      await HealthRepository.instance.saveVisits(finalVisits);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("병원 일정 동기화 완료!")),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("병원 일정 동기화 실패: $e")),
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

  void _loadData() {
    setState(() {
      _visits = HealthRepository.instance.getVisits();
      // sort by date descending
      _visits.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  void _showAddDialog({HospitalVisit? existingVisit}) async {
    final isEdit = existingVisit != null;
    final noteCtrl = TextEditingController(text: existingVisit?.note ?? "");
    DateTime? selectedDate = isEdit ? DateFormat('yyyy-MM-dd').parse(existingVisit.date) : null;
    
    TimeOfDay? visitTime;
    if (isEdit && existingVisit.visitTime.isNotEmpty) {
      final parts = existingVisit.visitTime.split(':');
      visitTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    
    TimeOfDay? alarmTime;
    if (isEdit && existingVisit.morningAlarmTime.isNotEmpty) {
      final parts = existingVisit.morningAlarmTime.split(':');
      alarmTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    String selectedRingtone = existingVisit?.ringtoneUri ?? 'default';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBuilder) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent, // Fix transparency overlay issue
          title: Text(isEdit ? "병원 일정 수정" : "병원 일정 추가", style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(selectedDate == null ? "방문 날짜 선택" : DateFormat('yyyy-MM-dd').format(selectedDate!), style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.calendar_today, color: Colors.white70),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              surface: Color(0xFF1E293B),
                              primary: Color(0xFF00E5FF),
                              onPrimary: Colors.black,
                              onSurface: Colors.white,
                            ),
                            dialogBackgroundColor: const Color(0xFF1E293B),
                            datePickerTheme: const DatePickerThemeData(
                              surfaceTintColor: Colors.transparent,
                              backgroundColor: Color(0xFF1E293B),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (d != null) setStateBuilder(() => selectedDate = d);
                  },
                ),
                ListTile(
                  title: Text(visitTime == null ? "방문 시간 선택" : visitTime!.format(context), style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.access_time, color: Colors.white70),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context, 
                      initialTime: visitTime ?? TimeOfDay.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              surface: Color(0xFF1E293B),
                              primary: Color(0xFF00E5FF),
                              onPrimary: Colors.black,
                              onSurface: Colors.white,
                            ),
                            dialogBackgroundColor: const Color(0xFF1E293B),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (t != null) setStateBuilder(() => visitTime = t);
                  },
                ),
                ListTile(
                  title: Text(alarmTime == null ? "아침 알람 시간" : alarmTime!.format(context), style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.alarm, color: Colors.white70),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context, 
                      initialTime: alarmTime ?? const TimeOfDay(hour: 7, minute: 0),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              surface: Color(0xFF1E293B),
                              primary: Color(0xFF00E5FF),
                              onPrimary: Colors.black,
                              onSurface: Colors.white,
                            ),
                            dialogBackgroundColor: const Color(0xFF1E293B),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (t != null) setStateBuilder(() => alarmTime = t);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: "메모", labelStyle: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRingtone,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: "알람 모드", labelStyle: TextStyle(color: Colors.white70)),
                  items: [
                    const DropdownMenuItem(value: 'default', child: Text("벨+진동")),
                    const DropdownMenuItem(value: 'vibrate', child: Text("진동")),
                    const DropdownMenuItem(value: 'silent', child: Text("무음")),
                    if (Platform.isAndroid)
                      const DropdownMenuItem(value: 'pick_custom', child: Text("🎵 단말기 시스템 벨소리 선택 (벨)...")),
                    if (selectedRingtone.startsWith('content://'))
                      DropdownMenuItem(value: selectedRingtone, child: const Text("🎵 선택된 시스템 벨소리 (벨)")),
                  ],
                  onChanged: (val) async {
                    if (val == 'pick_custom') {
                      final picked = await RingtonePickerHelper.pickRingtone();
                      setStateBuilder(() => selectedRingtone = picked);
                    } else if (val != null) {
                      setStateBuilder(() => selectedRingtone = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                if (selectedDate != null && visitTime != null) {
                  // Cancel old notification
                  if (isEdit) {
                    await NotificationService.instance.cancelHospitalNotification(existingVisit.id.hashCode.abs());
                  }

                  final newVisit = HospitalVisit(
                    id: isEdit ? existingVisit.id : const Uuid().v4(),
                    date: DateFormat('yyyy-MM-dd').format(selectedDate!),
                    visitTime: "${visitTime!.hour.toString().padLeft(2, '0')}:${visitTime!.minute.toString().padLeft(2, '0')}",
                    morningAlarmTime: alarmTime != null ? "${alarmTime!.hour.toString().padLeft(2, '0')}:${alarmTime!.minute.toString().padLeft(2, '0')}" : "",
                    note: noteCtrl.text,
                    ringtoneUri: selectedRingtone,
                  );

                  // Schedule alarm if morningAlarmTime is set
                  if (newVisit.morningAlarmTime.isNotEmpty) {
                    await NotificationService.instance.scheduleHospitalNotification(
                      newVisit.id.hashCode.abs(),
                      "🏥 병원 예약일입니다!",
                      "오늘 병원 방문 일정이 예약되어 있습니다: ${newVisit.visitTime} (${newVisit.note})",
                      newVisit.date,
                      newVisit.morningAlarmTime,
                      ringtoneUri: newVisit.ringtoneUri,
                    );
                  }

                  final list = HealthRepository.instance.getVisits();
                  if (isEdit) {
                    final index = list.indexWhere((e) => e.id == existingVisit.id);
                    if (index != -1) list[index] = newVisit;
                  } else {
                    list.add(newVisit);
                  }
                  await HealthRepository.instance.saveVisits(list);
                  _loadData();
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
                    const Text("🏥 병원 일정 관리", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
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
                          onPressed: _syncHospitalVisits,
                        ),
                    const SizedBox(width: 12),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                      onPressed: _showAddDialog,
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
                  ],
                )
              ],
            ),
            Expanded(
              child: _visits.isEmpty
                  ? const Center(child: Text("등록된 병원 일정이 없습니다.", style: TextStyle(color: Colors.white70)))
                  : ListView.builder(
                      itemCount: _visits.length,
                      itemBuilder: (context, index) {
                        final visit = _visits[index];
                        return Card(
                          color: const Color(0x1AFFFFFF),
                          child: ListTile(
                            title: Text("${visit.date} ${visit.visitTime}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              "알람: ${visit.morningAlarmTime.isNotEmpty ? visit.morningAlarmTime : '없음'}\n알람 모드: ${RingtonePickerHelper.getRingtoneDisplayName(visit.ringtoneUri)}\n메모: ${visit.note}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                  onPressed: () => _showAddDialog(existingVisit: visit),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () async {
                                    await NotificationService.instance.cancelHospitalNotification(visit.id.hashCode.abs());
                                    final list = HealthRepository.instance.getVisits()..removeWhere((e) => e.id == visit.id);
                                    await HealthRepository.instance.saveVisits(list);
                                    _loadData();
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
