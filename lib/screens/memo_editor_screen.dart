import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:intl/intl.dart';
import '../services/memo_storage.dart';

class MemoEditorScreen extends StatefulWidget {
  final RichMemo? initialMemo;

  const MemoEditorScreen({Key? key, this.initialMemo}) : super(key: key);

  @override
  _MemoEditorScreenState createState() => _MemoEditorScreenState();
}

class _MemoEditorScreenState extends State<MemoEditorScreen> {
  final MemoStorage _storage = MemoStorage();
  late bool _isEditing;
  late String _title;
  late int _createdAt;
  late List<MemoBlock> _blocks;

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  String _speechText = '';

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialMemo == null;
    _title = widget.initialMemo?.title ?? '';
    _createdAt = widget.initialMemo?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
    
    if (widget.initialMemo != null) {
      _blocks = MemoStorage.deserializeBlocks(widget.initialMemo!.contentJson);
    } else {
      _blocks = [MemoBlock(type: 'text', content: '')];
    }
  }

  Future<bool> _onWillPop() async {
    if (_isEditing && widget.initialMemo == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("저장 확인", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          content: const Text("작성 중인 메모를 저장하지 않고 나가시겠습니까?", style: TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("취소", style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("나가기", style: TextStyle(color: Color(0xFFFF5252))),
            ),
          ],
        ),
      );
      return confirm ?? false;
    }
    return true;
  }

  void _saveMemo() async {
    final contentJson = MemoStorage.serializeBlocks(_blocks);
    if (widget.initialMemo != null) {
      await _storage.updateMemo(widget.initialMemo!.id, _title, contentJson, _createdAt, pinned: widget.initialMemo!.pinned);
    } else {
      await _storage.addMemo(_title, contentJson, _createdAt);
    }
    Navigator.pop(context, true);
  }

  void _deleteMemo() async {
    if (widget.initialMemo != null) {
      await _storage.deleteMemo(widget.initialMemo!.id);
      Navigator.pop(context, true);
    }
  }

  void _insertImage(String path) {
    setState(() {
      _blocks.add(MemoBlock(type: 'image', content: path));
      _blocks.add(MemoBlock(type: 'text', content: ''));
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      final savedPath = await _storage.saveImageFile(File(pickedFile.path));
      _insertImage(savedPath);
    }
  }

  void _startListening() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) => print('onStatus: $status'),
      onError: (errorNotification) => print('onError: $errorNotification'),
    );
    if (available) {
      setState(() {
        _isListening = true;
        _speechText = '';
      });
      _speechToText.listen(
        onResult: (result) {
          setState(() {
            _speechText = result.recognizedWords;
          });
        },
      );
    }
  }

  void _stopListening() {
    _speechToText.stop();
    setState(() {
      _isListening = false;
      if (_speechText.isNotEmpty) {
        if (_blocks.last.type == 'text') {
          _blocks.last.content += (_blocks.last.content.isEmpty ? '' : '\n') + _speechText;
        } else {
          _blocks.add(MemoBlock(type: 'text', content: _speechText));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy년 MM월 dd일 HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_createdAt));

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (widget.initialMemo != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Color(0xFFFF5252)),
                onPressed: _deleteMemo,
              ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.check, color: Color(0xFF00E5FF)),
                onPressed: _saveMemo,
              )
            else
              IconButton(
                icon: const Icon(Icons.edit, color: Color(0xFF00E5FF)),
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (_isEditing)
                    TextField(
                      controller: TextEditingController(text: _title)..selection = TextSelection.collapsed(offset: _title.length),
                      onChanged: (val) => _title = val,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: "제목",
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        _title.isEmpty ? "제목 없는 문서" : _title,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ),
                  
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _isEditing ? 0.0 : 16.0, vertical: 4.0),
                    child: Text("📅 작성일자: $dateStr", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  const Divider(color: Color(0x33FFFFFF)),
                  const SizedBox(height: 16),
                  
                  ..._blocks.asMap().entries.map((entry) {
                    int idx = entry.key;
                    MemoBlock block = entry.value;

                    if (block.type == 'text') {
                      if (_isEditing) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: TextField(
                            controller: TextEditingController(text: block.content)..selection = TextSelection.collapsed(offset: block.content.length),
                            onChanged: (val) => block.content = val,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: block.fontSize,
                              fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: (block.content.isEmpty && _blocks.length == 1) ? "내용을 입력하세요..." : null,
                              hintStyle: const TextStyle(color: Colors.grey, fontSize: 18),
                              border: InputBorder.none,
                            ),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
                          child: Text(
                            block.content.isEmpty ? " " : block.content,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: block.fontSize,
                              fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }
                    } else if (block.type == 'image') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              width: MediaQuery.of(context).size.width * block.widthScale,
                              decoration: BoxDecoration(
                                color: const Color(0x11FFFFFF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: block.content.startsWith('/')
                                  ? Image.file(File(block.content), fit: BoxFit.contain)
                                  : Image.network(block.content, fit: BoxFit.contain), 
                            ),
                            if (_isEditing)
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _blocks.removeAt(idx);
                                    if (_blocks.isEmpty) {
                                      _blocks.add(MemoBlock(type: 'text', content: ''));
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }).toList(),
                  if (_isEditing)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _blocks.add(MemoBlock(type: 'text', content: ''));
                        });
                      },
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: const Icon(Icons.add, color: Color(0x66FFFFFF)),
                      ),
                    ),
                ],
              ),
            ),
            
            if (_isListening)
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("🗣️ 음성 기록 중... (수동 정지)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      height: 150,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        _speechText.isEmpty ? "말씀을 기다리고 있습니다..." : _speechText,
                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            _speechToText.stop();
                            setState(() => _isListening = false);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                          child: const Text("취소"),
                        ),
                        ElevatedButton(
                          onPressed: _stopListening,
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                          child: const Text("입력 완료", style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            if (_isEditing && !_isListening)
              Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Text("🖼️", style: TextStyle(fontSize: 24)),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                    IconButton(
                      icon: const Text("📷", style: TextStyle(fontSize: 24)),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                    IconButton(
                      icon: const Text("🎤", style: TextStyle(fontSize: 24)),
                      onPressed: _startListening,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
