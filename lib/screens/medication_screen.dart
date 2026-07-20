import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_models.dart';
import '../services/health_repository.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/ringtone_picker_helper.dart';

class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  int _selectedTab = 0;
  List<MedicationItem> _medications = [];
  List<MedicationLog> _todayLogs = [];
  Map<String, List<MedicationLog>> _allLogs = {};
  String _todayStr = "";
  bool _isSyncing = false;

  // Calendar
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _appStartDate;
  String? _nickname;
  
  @override
  void initState() {
    super.initState();
    _todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _selectedDay = DateTime.now();
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

  Future<void> _syncMedications() async {
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
      final localMedItems = HealthRepository.instance.getMedications();
      final localMedLogsMap = HealthRepository.instance.getAllLogs();
      final localMedLogs = localMedLogsMap.values.expand((element) => element).toList();

      if (localMedItems.isNotEmpty || localMedLogs.isNotEmpty) {
        await ApiService.syncMedications(
          userId,
          localMedItems.map((e) => e.toJson()).toList(),
          localMedLogs.map((e) => e.toJson()).toList(),
        );
      }

      final serverMedsMap = await ApiService.getMedications(userId);
      final serverMedItems = serverMedsMap != null ? (serverMedsMap['items'] as List).map((e) => MedicationItem.fromJson(e)).toList() : <MedicationItem>[];
      final serverMedLogs = serverMedsMap != null ? (serverMedsMap['logs'] as List).map((e) => MedicationLog.fromJson(e)).toList() : <MedicationLog>[];

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

      await ApiService.syncMedications(
        userId,
        finalMedItems.map((e) => e.toJson()).toList(),
        finalMedLogs.map((e) => e.toJson()).toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("약 복용 데이터 동기화 완료!")),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("약 복용 동기화 실패: $e")),
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
      _medications = HealthRepository.instance.getMedications();
      _todayLogs = HealthRepository.instance.getLogs(_todayStr);
      _allLogs = HealthRepository.instance.getAllLogs();

      DateTime? earliestDate;
      for (var med in _medications) {
        try {
          final d = DateFormat('yyyy-MM-dd').parse(med.createdAt);
          if (earliestDate == null || d.isBefore(earliestDate)) {
            earliestDate = d;
          }
        } catch (_) {}
      }
      for (var dateStr in _allLogs.keys) {
        try {
          final d = DateFormat('yyyy-MM-dd').parse(dateStr);
          if (earliestDate == null || d.isBefore(earliestDate)) {
            earliestDate = d;
          }
        } catch (_) {}
      }
      _appStartDate = earliestDate;
    });
  }

  int _generateNotificationId(String id, String time) {
    return (id + time).hashCode.abs();
  }

  void _showAddOrEditDialog({MedicationItem? existingItem}) {
    final isEdit = existingItem != null;
    final nameCtrl = TextEditingController(text: existingItem?.name ?? '');
    final timesCtrl = TextEditingController(text: existingItem?.times.join(', ') ?? '');
    String selectedRingtone = existingItem?.ringtoneUri ?? 'default';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(isEdit ? "약 수정" : "새로운 약 추가", style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "약 이름", labelStyle: TextStyle(color: Colors.white70)),
              ),
              TextField(
                controller: timesCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "시간 설정 (예: 08:00, 13:00)", labelStyle: TextStyle(color: Colors.white70)),
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
                    setStateDialog(() => selectedRingtone = picked);
                  } else if (val != null) {
                    setStateDialog(() => selectedRingtone = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                final times = timesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                if (nameCtrl.text.isNotEmpty && times.isNotEmpty) {
                  // If edit, cancel old alarms
                  if (isEdit) {
                    for (var time in existingItem.times) {
                      await NotificationService.instance.cancelMedicationNotification(_generateNotificationId(existingItem.id, time));
                    }
                  }

                  final itemId = isEdit ? existingItem.id : const Uuid().v4();
                  final newItem = MedicationItem(
                    id: itemId,
                    name: nameCtrl.text,
                    times: times,
                    createdAt: isEdit ? existingItem.createdAt : _todayStr,
                    ringtoneUri: selectedRingtone,
                  );

                  // Schedule new alarms
                  for (var time in times) {
                    await NotificationService.instance.scheduleDailyMedicationNotification(
                      _generateNotificationId(newItem.id, time),
                      "💊 약 복용 시간입니다!",
                      "${newItem.name}을(를) 복용할 시간이에요.",
                      time,
                      ringtoneUri: newItem.ringtoneUri,
                    );
                  }

                  final list = HealthRepository.instance.getMedications();
                  if (isEdit) {
                    final index = list.indexWhere((e) => e.id == itemId);
                    if (index != -1) list[index] = newItem;
                  } else {
                    list.add(newItem);
                  }
                  
                  await HealthRepository.instance.saveMedications(list);
                  _loadData();
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
              child: Text(isEdit ? "저장" : "추가"),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLog(MedicationItem med, String time, String targetDate) async {
    final targetLogs = HealthRepository.instance.getLogs(targetDate);
    final log = targetLogs.firstWhere(
      (l) => l.pillId == med.id && l.time == time,
      orElse: () => MedicationLog(date: targetDate, pillId: med.id, time: time, isTaken: false),
    );
    await HealthRepository.instance.setLog(targetDate, med.id, time, !log.isTaken);
    _loadData();
  }

  Widget _buildCalendarCell(DateTime day, {required bool isSelected, required bool isToday, required bool isOutside}) {
    final today = DateTime.now();
    final todayOnlyDate = DateTime(today.year, today.month, today.day);
    final dayOnlyDate = DateTime(day.year, day.month, day.day);

    bool isBeforeStart = false;
    if (_appStartDate != null) {
      final startOnlyDate = DateTime(_appStartDate!.year, _appStartDate!.month, _appStartDate!.day);
      if (dayOnlyDate.isBefore(startOnlyDate)) {
        isBeforeStart = true;
      }
    }

    Color cellBgColor = Colors.transparent;
    Color textColor = Colors.white;
    
    if (isOutside) {
      textColor = Colors.white38;
    } else if (day.weekday == DateTime.sunday || day.weekday == DateTime.saturday) {
      textColor = Colors.redAccent;
    }

    if (!isBeforeStart && _medications.isNotEmpty) {
      final totalReq = _medications.fold(0, (sum, m) => sum + m.times.length);
      if (totalReq > 0) {
        final dateStr = DateFormat('yyyy-MM-dd').format(day);
        final logs = _allLogs[dateStr] ?? [];
        final takenCount = logs.where((l) => l.isTaken).length;

        if (takenCount >= totalReq) {
          cellBgColor = const Color(0x334CAF50); // Green (Fully Taken)
        } else if (takenCount > 0) {
          cellBgColor = const Color(0x33FFB74D); // Yellow (Partially Taken)
        } else if (dayOnlyDate.isBefore(todayOnlyDate) || dayOnlyDate.isAtSameMomentAs(todayOnlyDate)) {
          cellBgColor = const Color(0x33E57373); // Red (Not Taken)
        }
      }
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cellBgColor,
        shape: BoxShape.circle,
        border: isSelected 
            ? Border.all(color: const Color(0xFF00E5FF), width: 2)
            : isToday 
                ? Border.all(color: Colors.white70, width: 1.5)
                : null,
      ),
      alignment: Alignment.center,
      child: Text(
        day.day.toString(),
        style: TextStyle(color: textColor, fontWeight: (isToday || isSelected) ? FontWeight.bold : FontWeight.normal),
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
                    const Text("💊 약 복용 관리", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
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
                          onPressed: _syncMedications,
                        ),
                    const SizedBox(width: 12),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                      onPressed: () => _showAddOrEditDialog(),
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
            Row(
              children: [
                TextButton(onPressed: () => setState(() => _selectedTab = 0), child: Text("오늘 현황", style: TextStyle(color: _selectedTab == 0 ? const Color(0xFF00E5FF) : Colors.white70))),
                TextButton(onPressed: () => setState(() => _selectedTab = 1), child: Text("월간 캘린더", style: TextStyle(color: _selectedTab == 1 ? const Color(0xFF00E5FF) : Colors.white70))),
              ],
            ),
            Expanded(
              child: _selectedTab == 0 ? _buildTodayList() : _buildCalendarView(),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTodayList() {
    if (_medications.isEmpty) {
      return const Center(child: Text("등록된 약이 없습니다.", style: TextStyle(color: Colors.white70)));
    }
    return ListView.builder(
      itemCount: _medications.length,
      itemBuilder: (context, index) {
        final med = _medications[index];
        return _buildMedicationCard(med, _todayStr, _todayLogs);
      },
    );
  }

  Widget _buildMedicationCard(MedicationItem med, String targetDate, List<MedicationLog> targetLogs) {
    return Card(
      color: const Color(0x1AFFFFFF),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(med.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () => _showAddOrEditDialog(existingItem: med),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        for (var time in med.times) {
                          await NotificationService.instance.cancelMedicationNotification(_generateNotificationId(med.id, time));
                        }
                        final list = HealthRepository.instance.getMedications()..removeWhere((e) => e.id == med.id);
                        await HealthRepository.instance.saveMedications(list);
                        _loadData();
                      },
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 8),
            Text("알람 시간: ${med.times.join(', ')}", style: const TextStyle(color: Colors.white70)),
            Text("알람 모드: ${RingtonePickerHelper.getRingtoneDisplayName(med.ringtoneUri)}", style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: med.times.map((time) {
                final isTaken = targetLogs.any((l) => l.pillId == med.id && l.time == time && l.isTaken);
                return Column(
                  children: [
                    Text(time, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    GestureDetector(
                      onTap: () => _toggleLog(med, time, targetDate),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isTaken ? Colors.green : Colors.white24,
                        ),
                        child: Icon(isTaken ? Icons.check : Icons.close, color: Colors.white, size: 20),
                      ),
                    )
                  ],
                );
              }).toList(),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarFormat: CalendarFormat.month,
          eventLoader: (day) {
            if (_medications.isEmpty) return [];
            final totalReq = _medications.fold(0, (sum, m) => sum + m.times.length);
            if (totalReq == 0) return [];

            final today = DateTime.now();
            final todayOnlyDate = DateTime(today.year, today.month, today.day);
            final dayOnlyDate = DateTime(day.year, day.month, day.day);

            if (_appStartDate != null) {
              final startOnlyDate = DateTime(_appStartDate!.year, _appStartDate!.month, _appStartDate!.day);
              if (dayOnlyDate.isBefore(startOnlyDate)) {
                return [];
              }
            }

            final dateStr = DateFormat('yyyy-MM-dd').format(day);
            final logs = _allLogs[dateStr] ?? [];
            final takenCount = logs.where((l) => l.isTaken).length;

            if (takenCount >= totalReq) {
              return ['green'];
            } else if (takenCount > 0) {
              return ['yellow'];
            } else if (dayOnlyDate.isBefore(todayOnlyDate) || dayOnlyDate.isAtSameMomentAs(todayOnlyDate)) {
              return ['red'];
            }
            return [];
          },
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: false, isToday: false, isOutside: false),
            todayBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: false, isToday: true, isOutside: false),
            selectedBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: true, isToday: false, isOutside: false),
            outsideBuilder: (context, day, focusedDay) => _buildCalendarCell(day, isSelected: false, isToday: false, isOutside: true),
          ),
          calendarStyle: const CalendarStyle(
            defaultTextStyle: TextStyle(color: Colors.white),
            weekendTextStyle: TextStyle(color: Colors.redAccent),
            outsideTextStyle: TextStyle(color: Colors.white38),
            selectedDecoration: BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            markersMaxCount: 1,
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
            leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
            rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildSelectedDateLogs(),
        ),
      ],
    );
  }

  Widget _buildSelectedDateLogs() {
    if (_selectedDay == null) return const SizedBox();
    
    final today = DateTime.now();
    final todayOnlyDate = DateTime(today.year, today.month, today.day);
    final selectedOnlyDate = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);

    if (selectedOnlyDate.isAfter(todayOnlyDate)) {
      return const Center(
        child: Text("아직 도래하지 않은 날짜의 일정은 표시되지 않습니다.", 
          style: TextStyle(color: Colors.white70, fontSize: 16))
      );
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final targetLogs = _allLogs[dateStr] ?? [];
    
    if (_medications.isEmpty) {
      return const Center(child: Text("등록된 약이 없습니다.", style: TextStyle(color: Colors.white70)));
    }

    return ListView.builder(
      itemCount: _medications.length,
      itemBuilder: (context, index) {
        final med = _medications[index];
        return _buildMedicationCard(med, dateStr, targetLogs);
      },
    );
  }
}
