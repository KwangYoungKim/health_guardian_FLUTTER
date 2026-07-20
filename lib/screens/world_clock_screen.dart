import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class WorldCity {
  final String name;
  final String flag;
  final double utcOffset; // in hours

  const WorldCity({required this.name, required this.flag, required this.utcOffset});
}

const List<WorldCity> availableCities = [
  WorldCity(name: '런던 (영국)', flag: '🇬🇧', utcOffset: 0.0),
  WorldCity(name: '파리 (프랑스)', flag: '🇫🇷', utcOffset: 1.0),
  WorldCity(name: '카이로 (이집트)', flag: '🇪🇬', utcOffset: 2.0),
  WorldCity(name: '두바이 (UAE)', flag: '🇦🇪', utcOffset: 4.0),
  WorldCity(name: '뉴델리 (인도)', flag: '🇮🇳', utcOffset: 5.5),
  WorldCity(name: '방콕 (태국)', flag: '🇹🇭', utcOffset: 7.0),
  WorldCity(name: '싱가포르', flag: '🇸🇬', utcOffset: 8.0),
  WorldCity(name: '베이징 (중국)', flag: '🇨🇳', utcOffset: 8.0),
  WorldCity(name: '서울 (한국)', flag: '🇰🇷', utcOffset: 9.0),
  WorldCity(name: '도쿄 (일본)', flag: '🇯🇵', utcOffset: 9.0),
  WorldCity(name: '시드니 (호주)', flag: '🇦🇺', utcOffset: 10.0),
  WorldCity(name: '뉴욕 (미국)', flag: '🇺🇸', utcOffset: -5.0),
  WorldCity(name: '로스앤젤레스 (미국)', flag: '🇺🇸', utcOffset: -8.0),
  WorldCity(name: '상파울루 (브라질)', flag: '🇧🇷', utcOffset: -3.0),
];

class WorldClockScreen extends StatefulWidget {
  const WorldClockScreen({Key? key}) : super(key: key);

  @override
  State<WorldClockScreen> createState() => _WorldClockScreenState();
}

class _WorldClockScreenState extends State<WorldClockScreen> {
  late Timer _timer;
  late DateTime _nowUtc;

  // Indices of the 3 selected world cities
  List<int> _selectedIndices = [0, 11, 1]; // Default: London, New York, Paris

  @override
  void initState() {
    super.initState();
    _nowUtc = DateTime.now().toUtc();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _nowUtc = DateTime.now().toUtc();
        });
      }
    });
    _loadPreferences();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedIndices[0] = prefs.getInt('world_clock_slot_0') ?? 0;
      _selectedIndices[1] = prefs.getInt('world_clock_slot_1') ?? 11;
      _selectedIndices[2] = prefs.getInt('world_clock_slot_2') ?? 1;
    });
  }

  Future<void> _savePreference(int slot, int cityIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('world_clock_slot_$slot', cityIndex);
    setState(() {
      _selectedIndices[slot] = cityIndex;
    });
  }

  void _showCitySelector(int slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "도시 선택",
                style: TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: availableCities.length,
                itemBuilder: (context, index) {
                  final city = availableCities[index];
                  final isSelected = _selectedIndices[slot] == index;
                  final offsetSign = city.utcOffset >= 0 ? '+' : '';
                  final offsetStr = "UTC $offsetSign${city.utcOffset.toStringAsFixed(1).replaceAll('.0', '')}";

                  return ListTile(
                    leading: Text(city.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(city.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(offsetStr, style: const TextStyle(color: Colors.grey)),
                    trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF00E5FF)) : null,
                    onTap: () {
                      _savePreference(slot, index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildClockCard(int slot) {
    final cityIndex = _selectedIndices[slot];
    final city = availableCities[cityIndex];

    // Calculate time for this city based on its offset
    final int minutesOffset = (city.utcOffset * 60).toInt();
    final DateTime cityTime = _nowUtc.add(Duration(minutes: minutesOffset));

    final String timeStr = DateFormat('HH:mm:ss').format(cityTime);
    final String dateStr = DateFormat('yyyy-MM-dd (E)', 'ko').format(cityTime);
    final String amPmStr = DateFormat('a', 'ko').format(cityTime);

    // Calculate difference from Seoul/Local Time (Seoul is UTC +9)
    final double diffFromSeoul = city.utcOffset - 9.0;
    final String diffSign = diffFromSeoul >= 0 ? '+' : '';
    final String diffStr = diffFromSeoul == 0
        ? "서울과 동일"
        : "서울보다 $diffSign${diffFromSeoul.toStringAsFixed(1).replaceAll('.0', '')}시간";

    return Card(
      color: const Color(0x22FFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(city.flag, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 8),
                      Text(
                        city.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    diffStr,
                    style: TextStyle(
                      color: diffFromSeoul == 0 ? const Color(0xFF00E5FF) : Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amPmStr,
                  style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showCitySelector(slot),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit, size: 14, color: Color(0xFF00E5FF)),
                  label: const Text(
                    "변경",
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current Local time in Seoul (UTC+9)
    final DateTime seoulTime = _nowUtc.add(const Duration(hours: 9));
    final String localTimeStr = DateFormat('HH:mm:ss').format(seoulTime);
    final String localDateStr = DateFormat('yyyy년 MM월 dd일 (E)', 'ko').format(seoulTime);

    return Scaffold(
      backgroundColor: Colors.transparent, // Let main background show through
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("🌐 세계 시계", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Local time header
                Container(
                  padding: const EdgeInsets.all(24.0),
                  margin: const EdgeInsets.symmetric(vertical: 16.0),
                  decoration: BoxDecoration(
                    color: const Color(0x3300E5FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "현재 서울 시간 (로컬)",
                        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localTimeStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        localDateStr,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4.0, bottom: 8.0),
                  child: Text(
                    "설정된 세계 시계 (3개)",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      _buildClockCard(0),
                      _buildClockCard(1),
                      _buildClockCard(2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
