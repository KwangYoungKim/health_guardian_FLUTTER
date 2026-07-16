import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class MemoBlock {
  final String id;
  final String type; // "text" or "image"
  String content;
  double fontSize;
  bool isBold;
  double widthScale;

  MemoBlock({
    String? id,
    required this.type,
    required this.content,
    this.fontSize = 18.0,
    this.isBold = false,
    this.widthScale = 1.0,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'content': content,
        'fontSize': fontSize,
        'isBold': isBold,
        'widthScale': widthScale,
      };

  factory MemoBlock.fromJson(Map<String, dynamic> json) => MemoBlock(
        id: json['id'] as String?,
        type: json['type'] as String? ?? 'text',
        content: json['content'] as String? ?? '',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
        isBold: json['isBold'] as bool? ?? false,
        widthScale: (json['widthScale'] as num?)?.toDouble() ?? 1.0,
      );
}

class RichMemo {
  final String id;
  String title;
  String contentJson;
  int lastModified;
  int createdAt;
  bool pinned;

  RichMemo({
    required this.id,
    required this.title,
    required this.contentJson,
    required this.lastModified,
    required this.createdAt,
    this.pinned = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'contentJson': contentJson,
        'lastModified': lastModified,
        'createdAt': createdAt,
        'pinned': pinned,
      };

  factory RichMemo.fromJson(Map<String, dynamic> json) => RichMemo(
        id: json['id'] as String,
        title: json['title'] as String,
        contentJson: json['contentJson'] as String,
        lastModified: json['lastModified'] as int,
        createdAt: json['createdAt'] as int? ?? json['lastModified'] as int,
        pinned: json['pinned'] as bool? ?? false,
      );
}

class MemoStorage {
  Future<File> get _memoFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/native_memos.json');
  }

  Future<void> cleanupOrphanedImages() async {
    try {
      final memos = await getAllMemos();
      final referencedImages = <String>{};
      for (var memo in memos) {
        final blocks = MemoStorage.deserializeBlocks(memo.contentJson);
        for (var block in blocks) {
          if (block.type == 'image' && block.content.isNotEmpty) {
            referencedImages.add(File(block.content).uri.pathSegments.last);
          }
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${directory.path}/memo_images');
      if (await imageDir.exists()) {
        final files = imageDir.listSync();
        for (var file in files) {
          if (file is File) {
            if (!referencedImages.contains(file.uri.pathSegments.last)) {
              await file.delete();
            }
          }
        }
      }
    } catch (e) {
      print('cleanupOrphanedImages error: $e');
    }
  }

  Future<List<RichMemo>> getAllMemos() async {
    try {
      final file = await _memoFile;
      if (!await file.exists()) {
        await file.writeAsString('[]');
        return [];
      }
      final jsonString = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final memos = jsonList.map((j) => RichMemo.fromJson(j)).toList();
      memos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return memos;
    } catch (e) {
      print('getAllMemos error: $e');
      return [];
    }
  }

  Future<void> saveAllMemos(List<RichMemo> memos) async {
    try {
      final file = await _memoFile;
      final jsonString = jsonEncode(memos.map((m) => m.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      print('saveAllMemos error: $e');
    }
  }

  Future<RichMemo> addMemo(String title, String contentJson, int createdAt) async {
    final memos = await getAllMemos();
    final newMemo = RichMemo(
      id: const Uuid().v4(),
      title: title,
      contentJson: contentJson,
      lastModified: DateTime.now().millisecondsSinceEpoch,
      createdAt: createdAt,
    );
    memos.add(newMemo);
    await saveAllMemos(memos);
    return newMemo;
  }

  Future<void> updateMemo(String id, String title, String contentJson, int createdAt, {bool pinned = false}) async {
    final memos = await getAllMemos();
    final index = memos.indexWhere((m) => m.id == id);
    if (index != -1) {
      memos[index].title = title;
      memos[index].contentJson = contentJson;
      memos[index].lastModified = DateTime.now().millisecondsSinceEpoch;
      memos[index].createdAt = createdAt;
      memos[index].pinned = pinned;
      await saveAllMemos(memos);
    }
  }

  Future<void> deleteMemo(String id) async {
    final memos = await getAllMemos();
    final memoToDelete = memos.firstWhere((m) => m.id == id, orElse: () => RichMemo(id: '', title: '', contentJson: '', lastModified: 0, createdAt: 0));
    if (memoToDelete.id.isNotEmpty) {
      final blocks = MemoStorage.deserializeBlocks(memoToDelete.contentJson);
      for (var block in blocks) {
        if (block.type == 'image') {
          final file = File(block.content);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    }
    memos.removeWhere((m) => m.id == id);
    await saveAllMemos(memos);
  }

  Future<String> saveImageFile(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${directory.path}/memo_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    final fileName = 'img_${const Uuid().v4()}.jpg';
    final savedImage = await imageFile.copy('${imageDir.path}/$fileName');
    return savedImage.path;
  }

  static String serializeBlocks(List<MemoBlock> blocks) {
    return jsonEncode(blocks.map((b) => b.toJson()).toList());
  }

  static List<MemoBlock> deserializeBlocks(String jsonString) {
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      final blocks = list.map((j) => MemoBlock.fromJson(j)).toList();
      if (blocks.isEmpty) {
        blocks.add(MemoBlock(type: 'text', content: ''));
      }
      return blocks;
    } catch (e) {
      return [MemoBlock(type: 'text', content: '')];
    }
  }
}
