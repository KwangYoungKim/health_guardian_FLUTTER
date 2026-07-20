import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/memo_storage.dart';
import 'memo_editor_screen.dart';
import '../services/api_service.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({Key? key}) : super(key: key);

  @override
  _MemoScreenState createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  final MemoStorage _storage = MemoStorage();
  List<RichMemo> _memos = [];
  String _searchQuery = "";
  Set<String> _collapsedGroups = {};
  bool _isSyncing = false;
  String? _nickname;

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _loadMemos();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nickname = prefs.getString('api_nickname');
      });
    }
  }

  Future<void> _syncMemos() async {
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
      final localMemos = await _storage.getAllMemos();

      if (localMemos.isNotEmpty) {
        await ApiService.syncRichMemos(userId, localMemos.map((e) => e.toJson()).toList());
      }

      final serverMemosJson = await ApiService.getRichMemos(userId);
      final serverMemos = serverMemosJson.map((e) => RichMemo.fromJson(e)).toList();

      final Map<String, RichMemo> mergedMemos = {};
      for (var m in serverMemos) mergedMemos[m.id] = m;
      for (var m in localMemos) {
        if (mergedMemos.containsKey(m.id)) {
          if (m.lastModified > mergedMemos[m.id]!.lastModified) {
            mergedMemos[m.id] = m;
          }
        } else {
          mergedMemos[m.id] = m;
        }
      }

      final finalMemos = mergedMemos.values.toList();
      await _storage.saveAllMemos(finalMemos);
      await ApiService.syncRichMemos(userId, finalMemos.map((e) => e.toJson()).toList());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("메모 동기화 완료!")),
        );
        _loadMemos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("메모 동기화 실패: $e")),
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

  Future<void> _loadMemos() async {
    final memos = await _storage.getAllMemos();
    setState(() {
      _memos = memos;
    });
  }

  String _getWeekString(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}년 ${date.month}월 ${(date.day - 1) ~/ 7 + 1}주차';
  }

  void _navigateToEditor([RichMemo? memo]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MemoEditorScreen(initialMemo: memo),
      ),
    );
    if (result == true) {
      _loadMemos();
    }
  }

  void _deleteMemo(RichMemo memo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("삭제 확인", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
        content: const Text("정말 삭제하시겠습니까?", style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("취소", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("삭제", style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.deleteMemo(memo.id);
      _loadMemos();
    }
  }

  void _togglePin(RichMemo memo) async {
    await _storage.updateMemo(
      memo.id,
      memo.title,
      memo.contentJson,
      memo.createdAt,
      pinned: !memo.pinned,
    );
    _loadMemos();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMemos = _memos.where((memo) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      if (memo.title.toLowerCase().contains(query)) return true;
      try {
        final blocks = MemoStorage.deserializeBlocks(memo.contentJson);
        for (var block in blocks) {
          if (block.type == 'text' && block.content.toLowerCase().contains(query)) {
            return true;
          }
        }
      } catch (_) {}
      return false;
    }).toList();

    final pinnedMemos = filteredMemos.where((m) => m.pinned).toList();
    final unpinnedMemos = filteredMemos.where((m) => !m.pinned).toList();

    final Map<String, List<RichMemo>> groups = {};
    for (var memo in unpinnedMemos) {
      final weekStr = _getWeekString(memo.createdAt);
      if (!groups.containsKey(weekStr)) {
        groups[weekStr] = [];
      }
      groups[weekStr]!.add(memo);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditor(),
        backgroundColor: const Color(0xFF00E5FF),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "메모",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
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
                            onPressed: _syncMemos,
                          ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "제목으로 메모 검색...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF334155),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: filteredMemos.isEmpty
                    ? const Center(
                        child: Text("저장된 메모가 없습니다.", style: TextStyle(color: Colors.grey)),
                      )
                    : ListView(
                        children: [
                          if (pinnedMemos.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text(
                                "📌 고정된 메모",
                                style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                              ),
                            ),
                            ...pinnedMemos.map((m) => _buildMemoCard(m)),
                          ],
                          ...groups.entries.map((entry) {
                            final weekStr = entry.key;
                            final weekMemos = entry.value;
                            final isCollapsed = _collapsedGroups.contains(weekStr);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isCollapsed) {
                                        _collapsedGroups.remove(weekStr);
                                      } else {
                                        _collapsedGroups.add(weekStr);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "📅 $weekStr (${weekMemos.length}개)",
                                          style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                                        ),
                                        Icon(
                                          isCollapsed ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isCollapsed) ...weekMemos.map((m) => _buildMemoCard(m)),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemoCard(RichMemo memo) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(memo.createdAt));

    return Card(
      color: const Color(0x33FFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToEditor(memo),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memo.title.isEmpty ? "제목 없음" : memo.title,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _togglePin(memo),
                    icon: Opacity(
                      opacity: memo.pinned ? 1.0 : 0.3,
                      child: Transform.rotate(
                        angle: memo.pinned ? 0.785 : 0, 
                        child: const Text("📌", style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _deleteMemo(memo),
                    child: const Text("삭제", style: TextStyle(color: Color(0xFFFF5252))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
