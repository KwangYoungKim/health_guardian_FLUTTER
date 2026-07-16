import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/health_models.dart';
import '../services/health_repository.dart';

class HospitalScreen extends StatefulWidget {
  const HospitalScreen({super.key});

  @override
  State<HospitalScreen> createState() => _HospitalScreenState();
}

class _HospitalScreenState extends State<HospitalScreen> {
  List<HospitalVisit> _visits = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _visits = HealthRepository.instance.getVisits();
      // sort by date descending
      _visits.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  void _showAddDialog() async {
    final noteCtrl = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? visitTime;
    TimeOfDay? alarmTime;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBuilder) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("병원 일정 추가", style: TextStyle(color: Colors.white)),
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
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setStateBuilder(() => selectedDate = d);
                  },
                ),
                ListTile(
                  title: Text(visitTime == null ? "방문 시간 선택" : visitTime!.format(context), style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.access_time, color: Colors.white70),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) setStateBuilder(() => visitTime = t);
                  },
                ),
                ListTile(
                  title: Text(alarmTime == null ? "아침 알람 시간" : alarmTime!.format(context), style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.alarm, color: Colors.white70),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 0));
                    if (t != null) setStateBuilder(() => alarmTime = t);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: "메모", labelStyle: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(
              onPressed: () {
                if (selectedDate != null && visitTime != null) {
                  final newVisit = HospitalVisit(
                    id: const Uuid().v4(),
                    date: DateFormat('yyyy-MM-dd').format(selectedDate!),
                    visitTime: "${visitTime!.hour.toString().padLeft(2, '0')}:${visitTime!.minute.toString().padLeft(2, '0')}",
                    morningAlarmTime: alarmTime != null ? "${alarmTime!.hour.toString().padLeft(2, '0')}:${alarmTime!.minute.toString().padLeft(2, '0')}" : "",
                    note: noteCtrl.text,
                  );
                  final list = HealthRepository.instance.getVisits()..add(newVisit);
                  HealthRepository.instance.saveVisits(list).then((_) {
                    _loadData();
                    Navigator.pop(ctx);
                  });
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
              children: [
                const Text("🏥 병원 일정 관리", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                  onPressed: _showAddDialog,
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
                              "알람: ${visit.morningAlarmTime.isNotEmpty ? visit.morningAlarmTime : '없음'}\n메모: ${visit.note}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () {
                                final list = HealthRepository.instance.getVisits()..removeWhere((e) => e.id == visit.id);
                                HealthRepository.instance.saveVisits(list).then((_) => _loadData());
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
