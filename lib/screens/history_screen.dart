import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; // Tambahkan ini
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _photos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllPhotos();
  }

  Future<void> _loadAllPhotos() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('termullog_'))
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      final List<Map<String, dynamic>> photos = [];
      for (var file in files) {
        try {
          final bytes = await file.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) {
            final fileName = p.basenameWithoutExtension(file.path);
            final parts = fileName.split('_');
            DateTime timestamp = DateTime.now();
            if (parts.length > 1) {
              final ms = int.tryParse(parts[1]);
              if (ms != null) timestamp = DateTime.fromMillisecondsSinceEpoch(ms);
            }
            photos.add({
              'path': file.path,
              'timestamp': timestamp,
              'thumbnail': bytes,
            });
          }
        } catch (e) {
          debugPrint('Error loading photo: $e');
        }
      }
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text('Riwayat Foto'),
        backgroundColor: const Color(0xFF1A1F2E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B8D4)))
          : _photos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Belum ada foto', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _photos.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    final timestamp = photo['timestamp'] as DateTime;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: const Color(0xFF1A1F2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photo['thumbnail'],
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          DateFormat('dd MMMM yyyy, HH:mm', 'id_ID').format(timestamp),
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          DateFormat('EEEE', 'id_ID').format(timestamp),
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.share, color: Color(0xFF00B8D4)),
                          onPressed: () async {
                            await Share.shareXFiles(
                              [XFile(photo['path'])],
                              text: 'Foto GPS dari TermulLog',
                            );
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _HistoryPhotoDetailScreen(imagePath: photo['path']),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class _HistoryPhotoDetailScreen extends StatelessWidget {
  final String imagePath;
  
  const _HistoryPhotoDetailScreen({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        foregroundColor: Colors.white,
        title: const Text('Detail Foto'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.file(File(imagePath)),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Tutup'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Share.shareXFiles(
                    [XFile(imagePath)],
                    text: 'Foto GPS dari TermulLog',
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Bagikan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B8D4),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
