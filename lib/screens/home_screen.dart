import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import '../core/camera_registry.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentPhotos = [];
  bool _isLoading = true;
  
  // Statistics
  int _totalPhotos = 0;
  double _avgAccuracy = 0;
  
  @override
  void initState() {
    super.initState();
    _loadRecentPhotos();
  }
  
  Future<void> _loadRecentPhotos() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('termullog_'))
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      
      // Sort by last modified (newest first)
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      final List<Map<String, dynamic>> photos = [];
      int total = 0;
      double totalAccuracy = 0;
      
      for (var file in files.take(20)) {
        try {
          final bytes = await file.readAsBytes();
          final image = img.decodeImage(bytes);
          if (image != null) {
            // Extract metadata from filename
            final fileName = p.basenameWithoutExtension(file.path);
            final parts = fileName.split('_');
            DateTime timestamp = DateTime.now();
            if (parts.length > 1) {
              final ms = int.tryParse(parts[1]);
              if (ms != null) timestamp = DateTime.fromMillisecondsSinceEpoch(ms);
            }
            
            // Warna dominan rata-rata (fallback)
            final avgColor = 0xFF1B4F72;
            
            photos.add({
              'path': file.path,
              'timestamp': timestamp,
              'thumbnail': bytes,
              'avgColor': avgColor,
            });
            total++;
            
            // Akurasi sementara (akan diambil dari metadata nanti)
            totalAccuracy += 10;
          }
        } catch (e) {
          debugPrint('Error loading photo: $e');
        }
      }
      
      setState(() {
        _recentPhotos = photos;
        _totalPhotos = total;
        _avgAccuracy = total > 0 ? totalAccuracy / total : 0;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load photos error: $e');
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _refreshPhotos() async {
    await _loadRecentPhotos();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00B8D4), Color(0xFF1B4F72)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'T',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'TermulLog',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                        _refreshPhotos();
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            // Stats Cards
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.photo_camera_outlined,
                        title: 'Total Foto',
                        value: '$_totalPhotos',
                        color: const Color(0xFF1B4F72),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.gps_fixed,
                        title: 'Rata-rata Akurasi',
                        value: '${_avgAccuracy.toStringAsFixed(0)}m',
                        color: const Color(0xFF00B8D4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Camera Button Hero
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final cameras = CameraRegistry.cameras;
                    if (cameras.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kamera tidak tersedia')),
                      );
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(cameras: cameras),
                      ),
                    );
                    _refreshPhotos();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00B8D4), Color(0xFF0077B6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00B8D4).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Decorative circles
                        Positioned(
                          right: -20,
                          top: -20,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: -30,
                          bottom: -30,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.camera_alt,
                                size: 48,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ambil Foto Baru',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Dengan GPS & Watermark',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Recent Photos Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Foto Terbaru',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HistoryScreen()),
                        );
                      },
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Lihat Semua'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF00B8D4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Recent Photos Grid
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00B8D4),
                  ),
                ),
              )
            else if (_recentPhotos.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada foto',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ambil foto pertama Anda',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final photo = _recentPhotos[index];
                      return _PhotoCard(
                        photo: photo,
                        onTap: () {
                          _viewPhotoDetail(photo['path']);
                        },
                      );
                    },
                    childCount: _recentPhotos.length,
                  ),
                ),
              ),
            
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
    );
  }
  
  void _viewPhotoDetail(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoDetailScreen(imagePath: path),
      ),
    );
  }
}

// ============================================================
// Stat Card Widget
// ============================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  
  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Photo Card Widget
// ============================================================

class _PhotoCard extends StatelessWidget {
  final Map<String, dynamic> photo;
  final VoidCallback onTap;
  
  const _PhotoCard({
    required this.photo,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    final timestamp = photo['timestamp'] as DateTime;
    final isToday = timestamp.day == DateTime.now().day &&
                    timestamp.month == DateTime.now().month &&
                    timestamp.year == DateTime.now().year;
    
    String timeStr;
    if (isToday) {
      timeStr = 'Hari ini ${DateFormat('HH:mm').format(timestamp)}';
    } else {
      timeStr = DateFormat('dd/MM/yy HH:mm').format(timestamp);
    }
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.memory(
                photo['thumbnail'],
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 140,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.broken_image, color: Colors.white38),
                ),
              ),
            ),
            
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.gps_fixed, size: 12, color: Color(0xFF00B8D4)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'GPS Location',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

// ============================================================
// Photo Detail Screen (Lightbox)
// ============================================================

class _PhotoDetailScreen extends StatefulWidget {
  final String imagePath;
  
  const _PhotoDetailScreen({required this.imagePath});
  
  @override
  State<_PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<_PhotoDetailScreen> {
  final TransformationController _transformController = TransformationController();
  
  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        foregroundColor: Colors.white,
        title: const Text('Detail Foto'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              await Share.shareXFiles(
                [XFile(widget.imagePath)],
                text: 'Foto GPS dari TermulLog',
              );
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.8,
        maxScale: 4.0,
        child: Center(
          child: Image.file(
            File(widget.imagePath),
            fit: BoxFit.contain,
          ),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Share.shareXFiles(
                    [XFile(widget.imagePath)],
                    text: 'Foto GPS dari TermulLog',
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Bagikan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B8D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
