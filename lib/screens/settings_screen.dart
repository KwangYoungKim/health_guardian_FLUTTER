import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'restore_screen.dart';
import 'register_screen.dart';
import 'world_clock_screen.dart';
import '../services/memo_storage.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text("데이터 관리", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync, color: Colors.white),
            title: const Text("클라우드 동기화 및 복원", style: TextStyle(color: Colors.white)),
            subtitle: const Text("서버에 저장된 데이터를 가져오거나 수동 동기화합니다.", style: TextStyle(color: Colors.white54)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RestoreScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text("로그아웃 및 계정 초기화", style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text("기기의 계정 설정을 지우고 최초 등록 화면으로 돌아갑니다.", style: TextStyle(color: Colors.white54)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("로그아웃 및 초기화"),
                  content: const Text("기기에 설정된 로그인 닉네임과 PIN 정보가 삭제되며, 로컬 데이터도 초기화됩니다. 계속하시겠습니까?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("확인", style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
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

                await prefs.remove('api_user_id');
                await prefs.remove('api_nickname');
                await prefs.remove('api_pin');
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
          const Divider(color: Color(0x33FFFFFF)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text("유틸리티", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ),
          ListTile(
            leading: const Icon(Icons.language, color: Colors.white),
            title: const Text("세계 시계", style: TextStyle(color: Colors.white)),
            subtitle: const Text("영국, 미국 등 해외 여러 도시의 현재 시간을 설정하고 조회합니다.", style: TextStyle(color: Colors.white54)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WorldClockScreen()),
              );
            },
          ),
          const Divider(color: Color(0x33FFFFFF)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text("정보", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text("버전 정보", style: TextStyle(color: Colors.white)),
            trailing: const Text("1.0.0", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
