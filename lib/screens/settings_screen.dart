import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'restore_screen.dart';
import 'register_screen.dart';
import 'world_clock_screen.dart';
import '../services/memo_storage.dart';
import '../services/api_service.dart';
import '../services/meet_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _nickname;
  String? _userId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nickname = prefs.getString('api_nickname');
      _userId = prefs.getString('api_user_id');
      _isLoading = false;
    });
  }

  Future<List<Map<String, String>>> _getAllCombinedUsers() async {
    final results = await Future.wait([
      MeetRepository.instance.getAllFirebaseUsers(),
      ApiService.getRegisteredUsers(),
    ]);

    final fbUsers = results[0];
    final dbUsers = results[1];

    final Map<String, Map<String, String>> merged = {};
    for (var u in fbUsers) {
      final id = u['id'] ?? '';
      final name = u['name'] ?? '';
      if (name.isNotEmpty) {
        merged['${id}_$name'] = u;
      }
    }
    for (var u in dbUsers) {
      final id = u['id'] ?? '';
      final name = u['name'] ?? '';
      if (name.isNotEmpty) {
        merged['${id}_$name'] = u;
      }
    }

    final list = merged.values.toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  // 🛡️ Super Admin (DragonKim) One-Stop User Management Dialog
  Future<void> _showSuperAdminUserManagementDialog() async {
    final TextEditingController inputController = TextEditingController();
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: Color(0xFF00E5FF), size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "슈퍼 관리자 사용자 원스톱 삭제",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                  maxWidth: double.maxFinite,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info Banner
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF00E5FF), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "삭제 대상 선택 시 백엔드 PostgreSQL DBMS와 Firebase에서 해당 정보가 동시 원스톱 삭제됩니다.",
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 🔍 2단계: 실시간 사용자 검색 및 입력
                      const Text(
                        "🔍 2단계: 사용자 검색 및 삭제 대상 닉네임 입력",
                        style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: inputController,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              onChanged: (val) {
                                setDialogState(() {
                                  searchQuery = val.trim();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: "삭제할 닉네임 입력 또는 검색 (예: Heidi)",
                                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 18),
                                suffixIcon: searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                                        onPressed: () {
                                          inputController.clear();
                                          setDialogState(() {
                                            searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final targetName = inputController.text.trim();
                              if (targetName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("삭제할 닉네임을 입력해 주세요.")),
                                );
                                return;
                              }

                              final confirm = await showDialog<bool>(
                                context: dialogCtx,
                                builder: (c) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E293B),
                                  title: const Text("4단계: 원스톱 삭제 최종 승인", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  content: Text(
                                    "닉네임 '$targetName' 계정 및 모든 관련 데이터를 백엔드 PostgreSQL DBMS 및 Firebase에서 동시 원스톱 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.",
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소", style: TextStyle(color: Colors.grey))),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text("양쪽 DB 연쇄 삭제 실행", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await ApiService.deleteUserByNickname(targetName);
                                final fbUsers = await MeetRepository.instance.getAllFirebaseUsers();
                                final match = fbUsers.where((u) => u['name']?.toLowerCase() == targetName.toLowerCase()).toList();
                                for (var u in match) {
                                  final uid = u['id'];
                                  if (uid != null) {
                                    await MeetRepository.instance.deleteFirebaseUserNode(uid);
                                  }
                                }

                                inputController.clear();
                                setDialogState(() {
                                  searchQuery = '';
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("'$targetName' 계정이 백엔드 DBMS 및 Firebase에서 원스톱 삭제되었습니다."),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text("원스톱 삭제", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),

                      // 📋 3단계: 현재 사용자 리스트 출력 및 선택
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "📋 3단계: 등록 사용자 리스트 (선택 클릭)",
                            style: TextStyle(color: Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          if (searchQuery.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                              child: Text("검색 중: '$searchQuery'", style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      FutureBuilder<List<Map<String, String>>>(
                        future: _getAllCombinedUsers(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text("오류 발생: ${snapshot.error}", style: const TextStyle(color: Colors.redAccent, fontSize: 12));
                          }
                          final users = snapshot.data ?? [];
                          final filteredUsers = users.where((u) {
                            if (searchQuery.isEmpty) return true;
                            final name = u['name']?.toLowerCase() ?? '';
                            final id = u['id']?.toLowerCase() ?? '';
                            final q = searchQuery.toLowerCase();
                            return name.contains(q) || id.contains(q);
                          }).toList();

                          if (filteredUsers.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                searchQuery.isNotEmpty ? "'$searchQuery' 검색 조건에 맞는 사용자가 없습니다." : "등록된 추가 사용자 목록이 없습니다.",
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: filteredUsers.map((user) {
                              final targetId = user['id'] ?? '';
                              final targetName = user['name'] ?? '';
                              final bool isSelf = (targetName == _nickname);

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: ListTile(
                                  dense: true,
                                  onTap: () {
                                    inputController.text = targetName;
                                    setDialogState(() {
                                      searchQuery = targetName;
                                    });
                                  },
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isSelf ? Colors.greenAccent.withOpacity(0.2) : const Color(0xFF00E5FF).withOpacity(0.2),
                                    child: Text(
                                      targetName.isNotEmpty ? targetName[0] : '?',
                                      style: TextStyle(
                                        color: isSelf ? Colors.greenAccent : const Color(0xFF00E5FF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          targetName,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSelf) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text("본인", style: TextStyle(color: Colors.greenAccent, fontSize: 9)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text("ID: $targetId", style: const TextStyle(color: Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis),
                                  trailing: isSelf
                                      ? const Icon(Icons.shield, color: Colors.greenAccent, size: 18)
                                      : InkWell(
                                          onTap: () async {
                                            inputController.text = targetName;
                                            final confirm = await showDialog<bool>(
                                              context: dialogCtx,
                                              builder: (c) => AlertDialog(
                                                backgroundColor: const Color(0xFF1E293B),
                                                title: const Text("4단계: 원스톱 삭제 최종 승인", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                                content: Text(
                                                  "사용자 '$targetName' (ID: $targetId) 계정과 관련 데이터를 백엔드 PostgreSQL DBMS 및 Firebase에서 동시 원스톱 삭제하시겠습니까?",
                                                  style: const TextStyle(color: Colors.white70),
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소", style: TextStyle(color: Colors.grey))),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const Text("양쪽 DB 연쇄 삭제 실행", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (confirm == true) {
                                              await ApiService.deleteUserByNickname(targetName);
                                              await ApiService.deleteUser(targetId, targetName);
                                              await MeetRepository.instance.deleteFirebaseUserNode(targetId);

                                              inputController.clear();
                                              setDialogState(() {
                                                searchQuery = '';
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text("'$targetName' 계정이 원스톱 삭제되었습니다."),
                                                    backgroundColor: Colors.redAccent,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text("선택 삭제", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text("닫기", style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDragonKim = (_nickname?.trim() == 'DragonKim');

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : ListView(
              children: [
                // 🛡️ DragonKim Super Admin Exclusive Management Section
                if (isDragonKim) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text("슈퍼 관리자 (DragonKim) 전용 권한", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4), width: 1.5),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.admin_panel_settings, color: Color(0xFF00E5FF), size: 28),
                      title: const Text(
                        "등록 사용자 관리 및 원스톱 통합 삭제",
                        style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: const Text(
                        "잘못 등록된 사용자를 백엔드 PostgreSQL DBMS와 Firebase Realtime DB에서 한 번에 원스톱 영구 삭제합니다.",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFF00E5FF)),
                      onTap: _showSuperAdminUserManagementDialog,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0x33FFFFFF)),
                ],

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
                        k == 'default_step_goal' ||
                        k == 'api_user_id' ||
                        k == 'api_nickname' ||
                        k == 'api_pin'
                      ).toList();
                      for (var key in keysToRemove) {
                        await prefs.remove(key);
                      }
                      await MemoStorage().saveAllMemos([]);

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
                  trailing: const Text("1.0.14", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }
}



