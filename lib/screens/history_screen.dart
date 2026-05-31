// lib/screens/history_screen.dart
// FINAL PRODUCTION – Riwayat foto dari folder dokumen permanen
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _photos = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 30;
  int _currentPage = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadAllPhotos(initial: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadAllPhotos();
      }
    }
  }

  Future<Directory> _getHistoryDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final historyDir = Directory('${appDir.path}/history');
    if (!await historyDir.exists()) {
      await historyDir.create(recursive: true);
    }
    return historyDir;
  }

  Future<void> _loadAllPhotos({bool initial = false}) async {
    if (initial) {
      setState(() {
        _isLoading = true;
        _photos = [];
        _currentPage = 0;
        _hasMore = true;
      });
    } else if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final historyDir = await _getHistoryDirectory();
      var files = historyDir.listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('termullog_'))
          .where((f) => f.path.endsWith('.jpg'))
          .toList();

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final start = _currentPage * _pageSize;
      final end = (start + _pageSize).clamp(0, files.length);
      if (start >= files.length) {
        if (mounted) setState(() => _hasMore = false);
        return;
      }

      final pageFiles = files.sublist(start, end);
      final List<Map<String, dynamic>> newPhotos = [];

      for (var file in pageFiles) {
        if (await file.exists()) {
          final fileName = p.basenameWithoutExtension(file.path);
          final parts = fileName.split('_');
          DateTime timestamp;
          if (parts.length > 1) {
            final ms = int.tryParse(parts[1]);
            if (ms != null) {
              timestamp = DateTime.fromMillisecondsSinceEpoch(ms);
            } else {
              timestamp = file.lastModifiedSync();
            }
          } else {
            timestamp = file.lastModifiedSync();
          }
          newPhotos.add({
            'path': file.path,
            'timestamp': timestamp,
          });
        }
      }

      if (mounted) {
        setState(() {
          if (initial) {
            _photos = newPhotos;
          } else {
            _photos.addAll(newPhotos);
          }
          _currentPage++;
          _hasMore = end < files.length;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePhoto(String path, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Foto'),
        content: const Text('Foto akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        if (mounted) {
          setState(() {
            _photos.removeAt(index);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto dihapus')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteAllPhotos() async {
    if (_photos.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Foto'),
        content: Text('Hapus ${_photos.length} foto secara permanen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final historyDir = await _getHistoryDirectory();
        final files = historyDir.listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('termullog_'))
            .where((f) => f.path.endsWith('.jpg'));
        for (final file in files) {
          await file.delete();
        }
        _loadAllPhotos(initial: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua foto dihapus')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  Future<void> _sharePhoto(String path) async {
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'image/jpeg')],
        text: 'Foto GPS dari TermulLog',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal berbagi: $e')),
        );
      }
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
        actions: [
          if (_photos.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              onPressed: _deleteAllPhotos,
              tooltip: 'Hapus Semua',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadAllPhotos(initial: true),
              tooltip: 'Muat Ulang',
            ),
          ],
        ],
      ),
      body: _isLoading && _photos.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B8D4)))
          : _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Belum ada foto', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text(
                        'Foto yang diambil akan tersimpan di sini',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _photos.length + (_hasMore ? 1 : 0),
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    if (index == _photos.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF00B8D4))),
                      );
                    }
                    final photo = _photos[index];
                    final timestamp = photo['timestamp'] as DateTime;
                    final path = photo['path'] as String;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: const Color(0xFF1A1F2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            cacheWidth: 120,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey.shade800,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey, size: 24),
                            ),
                          ),
                        ),
                        title: Text(
                          DateFormat('dd MMMM yyyy, HH:mm', 'id').format(timestamp),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        subtitle: Text(
                          DateFormat('EEEE', 'id').format(timestamp),
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share, color: Color(0xFF00B8D4)),
                              onPressed: () => _sharePhoto(path),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deletePhoto(path, index),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _HistoryPhotoDetailScreen(imagePath: path),
                            ),
                          ).then((_) => _loadAllPhotos(initial: true));
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
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Detail Foto'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            errorBuilder: (_, __, ___) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white38, size: 64),
                  SizedBox(height: 12),
                  Text('Foto tidak tersedia',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        color: Colors.grey.shade900,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Tutup'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Share.shareXFiles(
                    [XFile(imagePath, mimeType: 'image/jpeg')],
                    text: 'Foto GPS dari TermulLog',
                  );
                },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Bagikan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B8D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
