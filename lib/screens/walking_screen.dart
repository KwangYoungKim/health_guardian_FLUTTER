import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:health/health.dart';
import '../services/health_repository.dart';
import '../models/health_models.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class WalkingScreen extends StatefulWidget {
  const WalkingScreen({Key? key}) : super(key: key);

  @override
  State<WalkingScreen> createState() => _WalkingScreenState();
}

class _WalkingScreenState extends State<WalkingScreen> {
  bool _isWeekly = true;
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  DateTime _viewingWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday % 7));
  DateTime _viewingMonthCal = DateTime.now();
  
  StreamSubscription<StepCount>? _stepCountStream;
  StreamSubscription<Position>? _positionStream;
  Position? _lastKnownPosition;
  int _refreshTrigger = 0;
  String? _nickname;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _requestPermissionAndInit();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nickname = prefs.getString('api_nickname');
      });
    }
  }

  Future<void> _requestPermissionAndInit() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.example.health_guardian_flutter/ringtone_picker');
        await channel.invokeMethod('requestActivityRecognition');
      } catch (e) {
        print("Error requesting activity recognition: $e");
      }
    }

    _initStreams();
  }

  void _initStreams() {
    _stepCountStream = Pedometer.stepCountStream.listen((StepCount event) {
      _handleStepCount(event);
    }, onError: (error) {
      print("Pedometer error: $error");
    });

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "👟 Smart Health 걷기 추적 중",
          notificationText: "백그라운드에서도 실시간 이동 경로를 촘촘하게 기록하고 있습니다.",
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position? position) {
      if (position != null) {
        _handleLocationUpdate(position);
      }
    });
  }

  void _handleStepCount(StepCount event) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int currentTotalSteps = event.steps;
    int lastSensorValue = HealthRepository.instance.getLastSensorValue();
    
    if (lastSensorValue == -1) {
      HealthRepository.instance.saveLastSensorValue(currentTotalSteps);
      return;
    }
    
    int delta = currentTotalSteps - lastSensorValue;
    if (delta > 0) {
      final stepData = HealthRepository.instance.getStepData(today);
      int newSteps = stepData.steps + delta;
      HealthRepository.instance.saveStepData(StepData(date: today, steps: newSteps, goal: stepData.goal));
      HealthRepository.instance.saveLastSensorValue(currentTotalSteps);
      
      if (mounted) {
        setState(() { _refreshTrigger++; });
      }
    } else if (delta < 0) {
       HealthRepository.instance.saveLastSensorValue(currentTotalSteps);
    }
  }

  void _handleLocationUpdate(Position position) {
    if (position.accuracy > 50) return; // Ignore low accuracy (> 50m) GPS points
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var path = HealthRepository.instance.getDailyPath(today).toList();
    final nowMs = position.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    
    if (path.isNotEmpty) {
      final lastPoint = path.last;
      if (lastPoint.lat != 0.0 && lastPoint.lng != 0.0) {
        final timeDiffSec = (nowMs - lastPoint.timestamp) / 1000.0;
        final dist = Geolocator.distanceBetween(
          lastPoint.lat, lastPoint.lng,
          position.latitude, position.longitude,
        );
        // Ignore duplicate jitter if moved less than 1.5 meters
        if (dist < 1.5 && timeDiffSec < 10) return;
        // Only reject if dist > 500m AND time difference is under 30s (teleport spike)
        if (dist > 500 && timeDiffSec < 30) return;
      }
    }
    
    path.add(PathPoint(
      lat: position.latitude,
      lng: position.longitude,
      timestamp: nowMs,
    ));
    
    HealthRepository.instance.saveDailyPath(today, path);
    if (mounted) {
      setState(() {
        _lastKnownPosition = position;
        if (_selectedDate == today) {
          _refreshTrigger++;
        }
      });
    }
  }

  List<PathPoint> _filterGlitchPathPoints(List<PathPoint> raw) {
    final valid = raw.where((p) => p.lat != 0.0 && p.lng != 0.0).toList();
    if (valid.length < 2) return valid;

    List<PathPoint> filtered = [];
    for (int i = 0; i < valid.length; i++) {
      final curr = valid[i];
      if (filtered.isEmpty) {
        filtered.add(curr);
        continue;
      }
      final prev = filtered.last;
      final timeDiffSec = (curr.timestamp - prev.timestamp) / 1000.0;
      final dist = Geolocator.distanceBetween(prev.lat, prev.lng, curr.lat, curr.lng);

      // Accept point if distance <= 500m OR time gap >= 30s
      if (dist <= 500.0 || timeDiffSec >= 30.0) {
        filtered.add(curr);
      } else if (i + 1 < valid.length) {
        // If dist > 500m and time gap < 30s, check if next point is close to curr
        final next = valid[i + 1];
        final distToNext = Geolocator.distanceBetween(curr.lat, curr.lng, next.lat, next.lng);
        if (distToNext <= 500.0) {
          filtered.add(curr);
        }
      }
    }
    return filtered;
  }

  Future<void> _syncWalkingData() async {
    final userId = await ApiService.getUserId();
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
      // 1. Sync Daily Paths
      final localPathsMap = HealthRepository.instance.getAllDailyPaths();
      final localPaths = localPathsMap.entries.map((entry) {
        final date = entry.key;
        final points = entry.value;
        final jsonStr = jsonEncode(points.map((e) => e.toJson()).toList());
        return DailyPath(
          id: "${userId}_$date",
          userId: userId,
          date: date,
          pathJson: jsonStr,
        );
      }).toList();

      if (localPaths.isNotEmpty) {
        await ApiService.syncPaths(userId, localPaths.map((e) => e.toJson()).toList());
      }

      final serverPathsJson = await ApiService.getPaths(userId);
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

      for (var dp in mergedPaths.values) {
        try {
          final List<dynamic> jsonList = jsonDecode(dp.pathJson);
          final points = jsonList.map((e) => PathPoint.fromJson(e)).toList();
          await HealthRepository.instance.saveDailyPath(dp.date, points, syncToServer: false);
        } catch (e) {
          print("Error decoding path for ${dp.date}: $e");
        }
      }

      await ApiService.syncPaths(userId, mergedPaths.values.map((e) => e.toJson()).toList());

      // 2. Sync Location Memos
      final localLocMemosMap = HealthRepository.instance.getAllMemos();
      final localLocMemos = localLocMemosMap.values.expand((element) => element).toList();

      if (localLocMemos.isNotEmpty) {
        await ApiService.syncMemos(userId, localLocMemos.map((e) => e.toJson()).toList());
      }

      final serverLocMemosJson = await ApiService.getMemos(userId);
      final serverLocMemos = serverLocMemosJson.map((e) => LocationMemo.fromJson(e)).toList();

      final Map<String, LocationMemo> mergedLocMemos = {};
      for (var lm in serverLocMemos) mergedLocMemos["${lm.date}_${lm.id}"] = lm;
      for (var lm in localLocMemos) mergedLocMemos["${lm.date}_${lm.id}"] = lm;

      final locMemosByDate = <String, List<LocationMemo>>{};
      for (var lm in mergedLocMemos.values) {
        locMemosByDate.putIfAbsent(lm.date, () => []).add(lm);
      }
      for (final date in locMemosByDate.keys) {
        await HealthRepository.instance.saveMemos(date, locMemosByDate[date]!, syncToServer: false);
      }

      await ApiService.syncMemos(userId, mergedLocMemos.values.map((e) => e.toJson()).toList());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("걷기 데이터 및 메모 서버 동기화 완료!")),
        );
        setState(() {
          _refreshTrigger++;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("동기화 오류: $e")),
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

  Future<void> _syncWithFitnessApp() async {
    try {
      final health = Health();
      await health.configure();
      final types = [HealthDataType.STEPS];
      
      bool requested = await health.requestAuthorization(types);
      if (!requested) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("건강 데이터 접근 권한이 거부되었습니다.")),
          );
        }
        return;
      }
      
      final parsedDate = DateFormat('yyyy-MM-dd').parse(_selectedDate);
      final startOfDay = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      final endOfDay = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, 23, 59, 59);
      
      int? steps = await health.getTotalStepsInInterval(startOfDay, endOfDay);
      steps ??= 0;
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  Theme.of(context).platform == TargetPlatform.android ? Icons.sync : Icons.favorite,
                  color: Theme.of(context).platform == TargetPlatform.android ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55),
                ),
                const SizedBox(width: 8),
                const Text("걸음 수 동기화", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              "선택한 날짜($_selectedDate)에 피트니스 앱에서 가져온 걸음 수는 $steps 걸음입니다.\n이 걸음 수로 동기화하시겠습니까?",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("취소", style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () {
                  final stepData = HealthRepository.instance.getStepData(_selectedDate);
                  HealthRepository.instance.saveStepData(StepData(
                    date: _selectedDate,
                    steps: steps!,
                    goal: stepData.goal,
                  ));
                  setState(() {
                    _refreshTrigger++;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$_selectedDate 걸음 수가 $steps 걸음으로 동기화되었습니다.")),
                  );
                },
                child: const Text("동기화", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("동기화 중 오류가 발생했습니다: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    _stepCountStream?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _addCurrentLocationMemo([StateSetter? setDialogState]) async {
    Position? currentPos = _lastKnownPosition;
    if (currentPos == null) {
      try {
        currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        print("Error getting location: $e");
      }
    }

    if (currentPos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("현재 GPS 위치를 측정할 수 없습니다. 위치 권한을 확인해 주세요.")),
        );
      }
      return;
    }

    final TextEditingController _memoTextController = TextEditingController();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.edit_location_alt, color: Color(0xFF00E5FF)),
            SizedBox(width: 8),
            Text("📍 현위치 메모 추가", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "현재 위치: ${currentPos!.latitude.toStringAsFixed(4)}, ${currentPos.longitude.toStringAsFixed(4)}",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memoTextController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "이 위치에 남길 메모를 입력하세요...",
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF), width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () async {
              final text = _memoTextController.text.trim();
              if (text.isEmpty) return;

              final newMemo = LocationMemo(
                id: DateTime.now().millisecondsSinceEpoch,
                date: today,
                lat: currentPos!.latitude,
                lng: currentPos.longitude,
                memo: text,
                time: DateFormat('HH:mm').format(DateTime.now()),
              );

              await HealthRepository.instance.addLocationMemo(today, newMemo);
              if (mounted) {
                setState(() { _refreshTrigger++; });
                if (setDialogState != null) setDialogState(() {});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("📍 현위치 메모가 저장되었습니다.")),
                );
              }
            },
            child: const Text("저장", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _editLocationMemo(LocationMemo m, [StateSetter? setDialogState]) async {
    final TextEditingController _controller = TextEditingController(text: m.memo);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("✏️ 위치 메모 수정", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "수정할 메모를 입력하세요",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF), width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () async {
              final newText = _controller.text.trim();
              if (newText.isEmpty) return;

              final updated = LocationMemo(
                id: m.id,
                date: m.date,
                lat: m.lat,
                lng: m.lng,
                memo: newText,
                time: m.time,
              );

              await HealthRepository.instance.updateLocationMemo(m.date, updated);
              if (mounted) {
                setState(() { _refreshTrigger++; });
                if (setDialogState != null) setDialogState(() {});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✏️ 위치 메모가 수정되었습니다.")),
                );
              }
            },
            child: const Text("수정", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLocationMemo(LocationMemo m, [StateSetter? setDialogState]) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("🗑️ 메모 삭제", style: TextStyle(color: Colors.white)),
        content: const Text("해당 위치 메모를 삭제하시겠습니까?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await HealthRepository.instance.deleteLocationMemo(m.date, m.id);
              if (mounted) {
                setState(() { _refreshTrigger++; });
                if (setDialogState != null) setDialogState(() {});
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("🗑️ 메모가 삭제되었습니다.")),
                );
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showMapDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final rawPathPoints = HealthRepository.instance.getDailyPath(_selectedDate);
            final pathPoints = _filterGlitchPathPoints(rawPathPoints);
            final memos = HealthRepository.instance.getMemos(_selectedDate);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(16),
              child: Container(
                height: 560,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("$_selectedDate 걷기 경로", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text("기록된 위치: ${pathPoints.length}개", style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          onPressed: () => _addCurrentLocationMemo(setDialogState),
                          icon: const Icon(Icons.add_location_alt, size: 16, color: Colors.black),
                          label: const Text("현위치 메모", style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF00E5FF), width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: pathPoints.isNotEmpty 
                                ? LatLng(pathPoints.last.lat, pathPoints.last.lng)
                                : memos.isNotEmpty
                                  ? LatLng(memos.last.lat, memos.last.lng)
                                  : _lastKnownPosition != null
                                    ? LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude)
                                    : const LatLng(37.5665, 126.9780), // Default to Seoul
                              initialZoom: 17.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.health_guardian_flutter',
                              ),
                              if (pathPoints.length >= 2)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: pathPoints.map((p) => LatLng(p.lat, p.lng)).toList(),
                                      color: const Color(0xFF00E5FF),
                                      strokeWidth: 6.0,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (_lastKnownPosition != null)
                                    Marker(
                                      point: LatLng(_lastKnownPosition!.latitude, _lastKnownPosition!.longitude),
                                      width: 30,
                                      height: 30,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.3),
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: const BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ...memos.map((m) => Marker(
                                    point: LatLng(m.lat, m.lng),
                                    width: 40,
                                    height: 40,
                                    child: GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: const Color(0xFF1E293B),
                                            title: Text("📍 ${m.time} 메모", style: const TextStyle(color: Colors.white)),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(m.memo, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                                const SizedBox(height: 8),
                                                Text(
                                                  "좌표: ${m.lat.toStringAsFixed(4)}, ${m.lng.toStringAsFixed(4)}",
                                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              IconButton(
                                                icon: const Icon(Icons.edit, color: Color(0xFF00E5FF)),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  _editLocationMemo(m, setDialogState);
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  _deleteLocationMemo(m, setDialogState);
                                                },
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: const Text("닫기", style: TextStyle(color: Colors.grey)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                    ),
                                  )).toList(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (memos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.note_alt, color: Color(0xFF00E5FF), size: 14),
                          const SizedBox(width: 4),
                          Text("등록된 메모 (${memos.length}개)", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 54,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: memos.length,
                          itemBuilder: (ctx, i) {
                            final m = memos[i];
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x3300E5FF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0x6600E5FF)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text("📍 ${m.time}", style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                      SizedBox(
                                        width: 100,
                                        child: Text(m.memo, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _editLocationMemo(m, setDialogState),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteLocationMemo(m, setDialogState),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showSetGoalDialog() {
    final stepData = HealthRepository.instance.getStepData(_selectedDate);
    final TextEditingController _goalController = TextEditingController(text: stepData.goal.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("목표 걸음 수 설정", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _goalController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "목표 달성 수",
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final newGoal = int.tryParse(_goalController.text);
              if (newGoal != null && newGoal > 0) {
                HealthRepository.instance.setDefaultStepGoal(newGoal);
                HealthRepository.instance.saveStepData(StepData(date: _selectedDate, steps: stepData.steps, goal: newGoal));
                setState(() { _refreshTrigger++; });
                Navigator.pop(context);
              }
            },
            child: const Text("설정", style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("👟 Smart Health 걷기", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 20, fontWeight: FontWeight.bold)),
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
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.sync, color: Color(0xFF00E5FF)),
                            onPressed: _syncWalkingData,
                          ),
                    ],
                  ),
                ],
              ),
            ),
            // Top Toggle
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _isWeekly = true),
                    child: Text(
                      "주간 단위",
                      style: TextStyle(
                        fontSize: _isWeekly ? 24 : 16,
                        color: _isWeekly ? Colors.white : Colors.grey,
                        fontWeight: _isWeekly ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text("|", style: TextStyle(color: Colors.grey, fontSize: 20)),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _isWeekly = false),
                    child: Text(
                      "월간 단위",
                      style: TextStyle(
                        fontSize: !_isWeekly ? 24 : 16,
                        color: !_isWeekly ? Colors.white : Colors.grey,
                        fontWeight: !_isWeekly ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Steps Summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildSelectedDayDetails(),
            ),
            const SizedBox(height: 8),
            // Calendar header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildCalendarHeader(),
            ),
            // Calendar grid (takes remaining space if monthly, compact if weekly)
            _isWeekly
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                  child: _buildCalendarGrid(),
                )
              : Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                    child: _buildCalendarGrid(),
                  ),
                ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "fab_add_location_memo",
            onPressed: () => _addCurrentLocationMemo(),
            backgroundColor: const Color(0xFF00E5FF),
            child: const Icon(Icons.edit_location_alt, color: Colors.black),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: "fab_show_map",
            onPressed: _showMapDialog,
            backgroundColor: const Color(0xFF1E293B),
            child: const Icon(Icons.map, color: Color(0xFF00E5FF)),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    final monthStr = _isWeekly 
      ? DateFormat('yyyy년 M월').format(_viewingWeekStart)
      : DateFormat('yyyy년 M월').format(_viewingMonthCal);
      
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_left, color: Colors.white, size: 32),
            onPressed: () {
              setState(() {
                if (_isWeekly) {
                  _viewingWeekStart = _viewingWeekStart.subtract(const Duration(days: 7));
                } else {
                  _viewingMonthCal = DateTime(_viewingMonthCal.year, _viewingMonthCal.month - 1, 1);
                }
              });
            },
          ),
          Text(monthStr, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.arrow_right, color: Colors.white, size: 32),
            onPressed: () {
              setState(() {
                if (_isWeekly) {
                  _viewingWeekStart = _viewingWeekStart.add(const Duration(days: 7));
                } else {
                  _viewingMonthCal = DateTime(_viewingMonthCal.year, _viewingMonthCal.month + 1, 1);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysToRender = <DateTime?>[];
    if (_isWeekly) {
      for (int i = 0; i < 7; i++) {
        daysToRender.add(_viewingWeekStart.add(Duration(days: i)));
      }
    } else {
      final firstDayOfMonth = DateTime(_viewingMonthCal.year, _viewingMonthCal.month, 1);
      final daysInMonth = DateTime(_viewingMonthCal.year, _viewingMonthCal.month + 1, 0).day;
      
      int firstWeekday = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday
      if (firstWeekday == 7) firstWeekday = 0; // Make Sunday 0
      
      for (int i = 0; i < firstWeekday; i++) {
        daysToRender.add(null);
      }
      for (int i = 1; i <= daysInMonth; i++) {
        daysToRender.add(DateTime(_viewingMonthCal.year, _viewingMonthCal.month, i));
      }
    }

    final rows = <List<DateTime?>>[];
    for (int i = 0; i < daysToRender.length; i += 7) {
      rows.add(daysToRender.sublist(i, (i + 7 > daysToRender.length) ? daysToRender.length : i + 7));
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < 0) {
          setState(() {
            if (_isWeekly) {
              _viewingWeekStart = _viewingWeekStart.add(const Duration(days: 7));
            } else {
              _viewingMonthCal = DateTime(_viewingMonthCal.year, _viewingMonthCal.month + 1, 1);
            }
          });
        } else if (details.primaryVelocity! > 0) {
          setState(() {
            if (_isWeekly) {
              _viewingWeekStart = _viewingWeekStart.subtract(const Duration(days: 7));
            } else {
              _viewingMonthCal = DateTime(_viewingMonthCal.year, _viewingMonthCal.month - 1, 1);
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: _isWeekly ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ["일", "월", "화", "수", "목", "금", "토"].map((day) {
                Color color = Colors.white;
                if (day == "일") color = Colors.red;
                if (day == "토") color = Colors.blue;
                return Expanded(child: Center(child: Text(day, style: TextStyle(color: color, fontSize: 12))));
              }).toList(),
            ),
            const SizedBox(height: 4),
            ...rows.map((row) {
              final rowWidget = Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (index) {
                  if (index < row.length && row[index] != null) {
                    return Expanded(child: _buildDayCell(row[index]!));
                  } else {
                    return const Expanded(child: SizedBox());
                  }
                }),
              );
              return _isWeekly
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: rowWidget,
                    )
                  : Expanded(child: rowWidget);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final fullDate = DateFormat('yyyy-MM-dd').format(date);
    final dayStr = date.day.toString();
    
    final stepData = HealthRepository.instance.getStepData(fullDate);
    final steps = stepData.steps;
    final dailyGoal = stepData.goal > 0 ? stepData.goal : HealthRepository.instance.getDefaultStepGoal();
    final progress = (steps / dailyGoal).clamp(0.0, 1.0);
    
    final hasMemos = HealthRepository.instance.getMemos(fullDate).isNotEmpty;
    final hasPath = HealthRepository.instance.getDailyPath(fullDate).isNotEmpty;
    final isSelected = fullDate == _selectedDate;
    
    final sizeMod = _isWeekly ? 40.0 : 20.0;
    final textMod = _isWeekly ? 14.0 : 11.0;
    final isGoalReached = steps > 0 && steps >= dailyGoal;
    final cellColor = isGoalReached ? const Color(0xFFFFD700) : const Color(0xFF00E5FF);

    return GestureDetector(
      onTap: () {
        setState(() => _selectedDate = fullDate);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        padding: EdgeInsets.symmetric(vertical: _isWeekly ? 6.0 : 2.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x3300E5FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dayStr, style: TextStyle(color: Colors.white, fontSize: textMod)),
              SizedBox(height: _isWeekly ? 6 : 1),
              SizedBox(
                width: sizeMod,
                height: sizeMod,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      color: cellColor,
                      backgroundColor: const Color(0x33FFFFFF),
                      strokeWidth: _isWeekly ? 4.0 : 2.0,
                    ),
                    if (hasMemos || hasPath)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          width: _isWeekly ? 8 : 5,
                          height: _isWeekly ? 8 : 5,
                          decoration: BoxDecoration(
                            color: hasPath ? const Color(0xFF4285F4) : const Color(0xFFFFB74D),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isWeekly) ...[
                const SizedBox(height: 6),
                Text(
                  isGoalReached ? "⭐ $steps" : "$steps",
                  style: TextStyle(
                    color: steps > 0 ? cellColor : Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDayDetails() {
    final stepData = HealthRepository.instance.getStepData(_selectedDate);
    final dailyGoal = stepData.goal > 0 ? stepData.goal : HealthRepository.instance.getDefaultStepGoal();
    final progress = (stepData.steps / dailyGoal).clamp(0.0, 1.0);

    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final healthColor = isAndroid ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55);
    final healthIcon = isAndroid ? Icons.directions_walk : Icons.favorite;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Circular progress with steps count
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${stepData.steps}",
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Text("걸음", style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Right side stats with sync button overlay
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedDate,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${(progress * 100).toInt()}% 달성",
                        style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("목표", style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Row(
                            children: [
                              Text("$dailyGoal", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              GestureDetector(
                                onTap: _showSetGoalDialog,
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.edit, color: Colors.grey, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Sync button positioned at top-right of stats area
                Positioned(
                  top: 0,
                  right: 0,
                  child: Tooltip(
                    message: isAndroid ? "구글 피트니스 동기화" : "애플 건강 동기화",
                    child: InkWell(
                      onTap: _syncWithFitnessApp,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: healthColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: healthColor, width: 1.5),
                        ),
                        child: Icon(healthIcon, size: 16, color: healthColor),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
