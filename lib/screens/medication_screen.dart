import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/health_models.dart';
import '../services/health_repository.dart';

class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  int _selectedTab = 0;
  List<MedicationItem> _medications = [];
  List<MedicationLog> _todayLogs = [];
  String _todayStr = "";

  @override
  void initState() {
    super.initState();
    _todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadData();
  }

  void _loadData() {
    setState(() {
      _medications = HealthRepository.instance.getMedications();
      _todayLogs = HealthRepository.instance.getLogs(_todayStr);
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final timesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("새로운 약 추가", style: TextStyle(color: Colors.white)),
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
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              final times = timesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              if (nameCtrl.text.isNotEmpty && times.isNotEmpty) {
                final newItem = MedicationItem(
                  id: const Uuid().v4(),
                  name: nameCtrl.text,
                  times: times,
                  createdAt: _todayStr,
                );
                final list = HealthRepository.instance.getMedications()..add(newItem);
                HealthRepository.instance.saveMedications(list).then((_) {
                  _loadData();
                  Navigator.pop(ctx);
                });
              }
            },
            child: const Text("추가"),
          ),
        ],
      ),
    );
  }

  void _toggleLog(MedicationItem med, String time) async {
    final log = _todayLogs.firstWhere(
      (l) => l.pillId == med.id && l.time == time,
      orElse: () => MedicationLog(date: _todayStr, pillId: med.id, time: time, isTaken: false),
    );
    await HealthRepository.instance.setLog(_todayStr, med.id, time, !log.isTaken);
    _loadData();
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
                const Text("💊 약 복용 관리", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add, color: Color(0xFF00E5FF)),
                  onPressed: _showAddDialog,
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
              child: _selectedTab == 0 ? _buildTodayList() : const Center(child: Text("캘린더 기능은 준비중입니다.", style: TextStyle(color: Colors.white))),
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
        return Card(
          color: const Color(0x1AFFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(med.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        final list = HealthRepository.instance.getMedications()..removeWhere((e) => e.id == med.id);
                        HealthRepository.instance.saveMedications(list).then((_) => _loadData());
                      },
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text("알람 시간: ${med.times.join(', ')}", style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: med.times.map((time) {
                    final isTaken = _todayLogs.any((l) => l.pillId == med.id && l.time == time && l.isTaken);
                    return Column(
                      children: [
                        Text(time, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        GestureDetector(
                          onTap: () => _toggleLog(med, time),
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
      },
    );
  }
}
