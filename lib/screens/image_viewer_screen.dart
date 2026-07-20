import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ImageViewerScreen extends StatefulWidget {
  final String imagePath;

  const ImageViewerScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _isDownloading = false;
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition;
      if (position != null) {
        _transformationController.value = Matrix4.identity()
          ..translate(-position.dx * 1.5, -position.dy * 1.5)
          ..scale(2.5);
      } else {
        _transformationController.value = Matrix4.identity()..scale(2.0);
      }
    }
  }

  Future<void> _downloadImage() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      String localPath = widget.imagePath;

      // 1. If it's a remote URL, download it to a temp file first
      if (localPath.startsWith('http')) {
        final uri = Uri.parse(localPath);
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final filename = localPath.split('/').last.split('?').first;
          final file = File('${tempDir.path}/$filename');
          await file.writeAsBytes(response.bodyBytes);
          localPath = file.path;
        } else {
          throw Exception("이미지 다운로드 실패 (HTTP ${response.statusCode})");
        }
      }

      // 2. Call the native save channel
      const channel = MethodChannel('com.example.health_guardian_flutter/ringtone_picker');
      final bool success = await channel.invokeMethod('saveImageToGallery', {
        'filePath': localPath,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? "🎉 사진첩(갤러리)에 저장되었습니다!" : "❌ 저장에 실패했습니다."),
            backgroundColor: success ? Colors.teal : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ 저장 중 오류 발생: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isNetwork = widget.imagePath.startsWith('http');
    final filename = widget.imagePath.split('/').last;
    final fallbackUrl = 'http://116.123.208.138:8099/api/images/$filename';

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = Image.network(
        widget.imagePath,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.broken_image, size: 80, color: Colors.grey),
          );
        },
      );
    } else {
      imageWidget = Image.file(
        File(widget.imagePath),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // If local file fails, fall back to network sync folder
          return Image.network(
            fallbackUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
            },
            errorBuilder: (context, err, st) {
              return const Center(
                child: Icon(Icons.broken_image, size: 80, color: Colors.grey),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: const Text("이미지 크게 보기", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _isDownloading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download, color: Color(0xFF00E5FF)),
                  tooltip: "갤러리에 다운로드",
                  onPressed: _downloadImage,
                ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 4.0,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              child: imageWidget,
            ),
          ),
        ),
      ),
    );
  }
}
