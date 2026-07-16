// lib/screens/walking_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/health_repository.dart';
import '../models/health_models.dart';

class WalkingScreen extends StatefulWidget {
  const WalkingScreen({Key? key}) : super(key: key);

  @override
  State<WalkingScreen> createState() => _WalkingScreenState();
}

class _WalkingScreenState extends State<WalkingScreen> {
  int _steps = 0;
  int _goal = 10000;
  final TextEditingController _goalController = TextEditingController();
  
  Timer? _mockTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initMockPedometer();
  }
  
  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }

  void _loadData() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final stepData = HealthRepository.instance.getStepData(today);
    setState(() {
      _steps = stepData.steps;
      _goal = stepData.goal;
      _goalController.text = stepData.goal.toString();
    });
  }

  void _initMockPedometer() {
    // macOS 환경의 CocoaPods 설치 문제로 iOS 네이티브 플러그인 빌드가 불가능하여, 
    // 임시로 1초에 2걸음씩 증가하도록 시뮬레이션합니다.
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _steps += 2;
        });
        final today = DateTime.now().toIso8601String().split('T')[0];
        HealthRepository.instance.saveStepData(StepData(date: today, steps: _steps, goal: _goal));
      }
    });
  }

  Future<void> _setGoal() async {
    final newGoal = int.tryParse(_goalController.text);
    if (newGoal != null && newGoal > 0) {
      await HealthRepository.instance.setDefaultStepGoal(newGoal);
      final today = DateTime.now().toIso8601String().split('T')[0];
      await HealthRepository.instance.saveStepData(StepData(date: today, steps: _steps, goal: newGoal));
      setState(() {
        _goal = newGoal;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('목표가 설정되었습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _goal > 0 ? (_steps / _goal).clamp(0.0, 1.0) : 0.0;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Text("오늘의 걸음 (모의 동작 중)", style: TextStyle(color: Colors.white70, fontSize: 18)),
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 15,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF00E5FF),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        "$_steps",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "걸음",
                        style: TextStyle(color: Colors.white70, fontSize: 20),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Card(
                color: Colors.white12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text("목표 걸음 수", style: TextStyle(color: Colors.white)),
                      ),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _goalController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _setGoal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                        child: const Text("설정"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "달성률: ${(progress * 100).toStringAsFixed(1)}%",
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "안내: 현재 Mac 환경에 iOS 빌드용 패키지 관리자(CocoaPods)가 미설치 상태여서 네이티브 센서 접근이 불가능합니다. 임시로 가상의 걸음 수가 올라가도록 조치했습니다.",
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
