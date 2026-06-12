// lib/screens/home_screen.dart
// TOTAL REBUILD – TimeMark-inspired home screen
// Dark navy theme, recent photos grid, clean action bar

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/camera_registry.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_PhotoEntry> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<Directory> _histDir() async {
    final d = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/history');
    await d.create(recursive: true);
    return d;
  }

  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    try {
      final dir = await _histDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.jpg') &&
              p.basename(f.path).startsWith('termullog_'))
          .toList()
        ..sort((a, b) =>
            b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final entries = <_PhotoEntry>[];
      for (final f in files.take(50)) {
        final base = p.basenameWithoutExtension(f.path);
        final ms = int.tryParse(base.split('_').elementAtOrNull(1) ?? '');
        entries.add(_PhotoEntry(
          path: f.path,
          timestamp: ms != null
              ? DateTime.fromMillisecondsSinceEpoch(ms)
              : f.lastModifiedSync(),
        ));
      }
      if (mounted) setState(() { _photos = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const CameraScreen()), // ← Perbaikan
    );
    _loadPhotos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B16),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatsBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCamera,
        backgroundColor: const Color(0xFFE63946),
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text('Ambil Foto',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(
        children: [
          // Logo
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE63946), Color(0xFF9B2335)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('T',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TermulLog',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                Text('Timestamp Camera',
                    style: TextStyle(color: Color(0xFF4A5568), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white54, size: 24),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white54, size: 24),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()));
              _loadPhotos();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _StatChip(
              label: '${_photos.length}',
              sub: 'Foto',
              icon: Icons.photo_library_outlined),
          const SizedBox(width: 12),
          _StatChip(
              label: _photos.isEmpty
                  ? '—'
                  : DateFormat('dd MMM').format(_photos.first.timestamp),
              sub: 'Terbaru',
              icon: Icons.schedule),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child:
              CircularProgressIndicator(color: Color(0xFF1E90FF)));
    }
    if (_photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_camera_outlined,
                color: Color(0xFF2A3456), size: 64),
            const SizedBox(height: 16),
            const Text('Belum ada foto',
                style: TextStyle(
                    color: Color(0xFF3A4570), fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Tap tombol kamera untuk mulai',
                style: TextStyle(
                    color: Color(0xFF2A3456), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      color: const Color(0xFF1E90FF),
      backgroundColor: const Color(0xFF0A0E1A),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: _photos.length,
        itemBuilder: (_, i) => _PhotoCard(
          entry: _photos[i],
          onShare: () => _share(_photos[i].path),
          onDelete: () => _delete(_photos[i]),
        ),
      ),
    );
  }

  void _share(String path) {
    Share.shareXFiles([XFile(path)]);
  }

  Future<void> _delete(_PhotoEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Hapus foto?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Foto akan dihapus dari histori.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus',
                  style: TextStyle(color: Color(0xFFE63946)))),
        ],
      ),
    );
    if (ok == true) {
      try { await File(entry.path).delete(); } catch (_) {}
      _loadPhotos();
    }
  }
}

class _PhotoEntry {
  final String path;
  final DateTime timestamp;
  const _PhotoEntry({required this.path, required this.timestamp});
}

class _StatChip extends StatelessWidget {
  final String label;
  final String sub;
  final IconData icon;

  const _StatChip(
      {required this.label, required this.sub, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1A2540)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1E90FF)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              Text(sub,
                  style: const TextStyle(
                      color: Color(0xFF3A4570), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final _PhotoEntry entry;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _PhotoCard({
    required this.entry,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(entry.path), fit: BoxFit.cover),
            // Timestamp overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Text(
                  DateFormat('dd/MM/yy HH:mm').format(entry.timestamp),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0E1A),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share, color: Color(0xFF1E90FF)),
            title: const Text('Bagikan',
                style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); onShare(); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Color(0xFFE63946)),
            title: const Text('Hapus',
                style: TextStyle(color: Color(0xFFE63946))),
            onTap: () { Navigator.pop(context); onDelete(); },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

