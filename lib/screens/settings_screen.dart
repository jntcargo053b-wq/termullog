// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../services/settings_service.dart';
import '../services/settings_cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  WatermarkLayout _selectedLayout = WatermarkLayout.cinematic;
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  String _watermarkPosition = 'bottom';
  double _opacity = 0.85;
  bool _showBorder = true;
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = 'HH:mm:ss';
  bool _showMiniMap = true;
  int _mapZoomLevel = 16;
  String _mapSize = 'medium';
  String _fontSize = 'normal';
  String _themeMode = 'dark';
  int _imageQuality = 90;
  bool _keepScreenOn = true;
  bool _useHighAccuracy = true;
  bool _autoSave = false;
  int _tempFileCount = 0;
  String _tempFileSize = '0 KB';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheInfo();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final layout = await SettingsService.getWatermarkLayout();
    final showWeather = await SettingsService.getShowWeather();
    final showAccuracy = await SettingsService.getShowAccuracy();
    final showAddress = await SettingsService.getShowAddress();
    final showCoordinates = await SettingsService.getShowCoordinates();
    final position = await SettingsService.getWatermarkPosition();
    final opacity = await SettingsService.getOpacity();
    final showBorder = await SettingsService.getShowBorder();
    final dateFormat = await SettingsService.getDateFormat();
    final timeFormat = await SettingsService.getTimeFormat();
    final showMiniMap = await SettingsService.getShowMiniMap();
    final mapZoomLevel = await SettingsService.getMapZoomLevel();
    final mapSize = await SettingsService.getMapSize();
    final fontSize = await SettingsService.getFontSize();
    final themeMode = await SettingsService.getThemeMode();
    final imageQuality = await SettingsService.getImageQuality();
    final keepScreenOn = await SettingsService.getKeepScreenOn();
    final useHighAccuracy = await SettingsService.getUseHighAccuracy();
    final autoSave = await SettingsService.getAutoSave();

    setState(() {
      _selectedLayout = layout;
      _showWeather = showWeather;
      _showAccuracy = showAccuracy;
      _showAddress = showAddress;
      _showCoordinates = showCoordinates;
      _watermarkPosition = position;
      _opacity = opacity;
      _showBorder = showBorder;
      _dateFormat = dateFormat;
      _timeFormat = timeFormat;
      _showMiniMap = showMiniMap;
      _mapZoomLevel = mapZoomLevel;
      _mapSize = mapSize;
      _fontSize = fontSize;
      _themeMode = themeMode;
      _imageQuality = imageQuality;
      _keepScreenOn = keepScreenOn;
      _useHighAccuracy = useHighAccuracy;
      _autoSave = autoSave;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await SettingsService.setWatermarkLayout(_selectedLayout);
    await SettingsService.setShowWeather(_showWeather);
    await SettingsService.setShowAccuracy(_showAccuracy);
    await SettingsService.setShowAddress(_showAddress);
    await SettingsService.setShowCoordinates(_showCoordinates);
    await SettingsService.setWatermarkPosition(_watermarkPosition);
    await SettingsService.setOpacity(_opacity);
    await SettingsService.setShowBorder(_showBorder);
    await SettingsService.setDateFormat(_dateFormat);
    await SettingsService.setTimeFormat(_timeFormat);
    await SettingsService.setShowMiniMap(_showMiniMap);
    await SettingsService.setMapZoomLevel(_mapZoomLevel);
    await SettingsService.setMapSize(_mapSize);
    await SettingsService.setFontSize(_fontSize);
    await SettingsService.setThemeMode(_themeMode);
    await SettingsService.setImageQuality(_imageQuality);
    await SettingsService.setKeepScreenOn(_keepScreenOn);
    await SettingsService.setUseHighAccuracy(_useHighAccuracy);
    await SettingsService.setAutoSave(_autoSave);

    SettingsCache.invalidate();

    _applyThemeMode();
    _applyKeepScreenOn();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('Pengaturan berhasil disimpan'),
            ],
          ),
          backgroundColor: Color(0xFF1A1F2E),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyThemeMode() {}
  
  void _applyKeepScreenOn() {
    if (_keepScreenOn) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _resetToDefault() async {
    await SettingsService.resetAllSettings();
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text('Pengaturan berhasil direset ke default'),
            ],
          ),
          backgroundColor: Color(0xFF1A1F2E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadCacheInfo() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => path.basename(f.path).startsWith('termullog_'))
          .toList();
      int totalSize = 0;
      for (final file in files) {
        totalSize += await file.length();
      }
      setState(() {
        _tempFileCount = files.length;
        if (totalSize < 1024) {
          _tempFileSize = '$totalSize B';
        } else if (totalSize < 1024 * 1024) {
          _tempFileSize = '${(totalSize / 1024).toStringAsFixed(1)} KB';
        } else {
          _tempFileSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
      });
    } catch (e) {
      debugPrint('Load cache info error: $e');
    }
  }

  Future<void> _clearTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => path.basename(f.path).startsWith('termullog_'))
          .toList();
      int deletedCount = 0;
      for (final file in files) {
        try {
          await file.delete();
          deletedCount++;
        } catch (e) {
          debugPrint('Failed to delete: ${file.path} - $e');
        }
      }
      await _loadCacheInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil menghapus $deletedCount file temporary'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membersihkan cache'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Colors.grey.shade800;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text('Pengaturan', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1A1F2E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Color(0xFF00B8D4)),
            onPressed: _saveSettings,
            tooltip: 'Simpan Pengaturan',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B8D4)))
          : ListView(
              children: [
                _buildPreviewCard(),
                const SizedBox(height: 8),
                _buildSectionHeader('GAYA TAMPILAN', Icons.style),
                ...WatermarkLayout.values.map((layout) => _buildLayoutOption(layout)),
                _buildSliderTile(
                  title: 'Transparansi Background', subtitle: 'Atur kegelapan background watermark',
                  value: _opacity, min: 0.3, max: 1.0, divisions: 14,
                  onChanged: (value) => setState(() => _opacity = value), icon: Icons.opacity,
                ),
                _buildSwitchTile(
                  title: 'Tampilkan Border', subtitle: 'Menampilkan border di sekitar watermark',
                  value: _showBorder, onChanged: (value) => setState(() => _showBorder = value), icon: Icons.border_style,
                ),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('INFORMASI YANG DITAMPILKAN', Icons.info_outline),
                _buildSwitchTile(title: 'Tampilkan Cuaca', subtitle: 'Menampilkan informasi cuaca di watermark', value: _showWeather, onChanged: (value) => setState(() => _showWeather = value), icon: Icons.wb_sunny),
                _buildSwitchTile(title: 'Tampilkan Akurasi GPS', subtitle: 'Menampilkan tingkat akurasi GPS dalam meter', value: _showAccuracy, onChanged: (value) => setState(() => _showAccuracy = value), icon: Icons.gps_fixed),
                _buildSwitchTile(title: 'Tampilkan Alamat', subtitle: 'Menampilkan alamat lengkap lokasi', value: _showAddress, onChanged: (value) => setState(() => _showAddress = value), icon: Icons.location_on),
                _buildSwitchTile(title: 'Tampilkan Koordinat', subtitle: 'Menampilkan koordinat GPS', value: _showCoordinates, onChanged: (value) => setState(() => _showCoordinates = value), icon: Icons.map),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('FORMAT TANGGAL & WAKTU', Icons.calendar_today),
                _buildDropdownTile(title: 'Format Tanggal', subtitle: 'Pilih format tampilan tanggal', value: _dateFormat, items: const ['dd/MM/yyyy', 'yyyy-MM-dd', 'dd MMM yyyy', 'MMMM dd, yyyy', 'dd MMMM yyyy'], onChanged: (value) => setState(() => _dateFormat = value!), icon: Icons.calendar_today),
                _buildDropdownTile(title: 'Format Waktu', subtitle: 'Pilih format tampilan waktu', value: _timeFormat, items: const ['HH:mm:ss', 'HH:mm', 'hh:mm:ss a', 'hh:mm a'], onChanged: (value) => setState(() => _timeFormat = value!), icon: Icons.access_time),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('POSISI WATERMARK', Icons.vertical_align_center),
                _buildRadioTile(title: 'Bawah', subtitle: 'Watermark di bagian bawah foto', value: 'bottom', groupValue: _watermarkPosition, onChanged: (value) => setState(() => _watermarkPosition = value!), icon: Icons.vertical_align_bottom),
                _buildRadioTile(title: 'Atas', subtitle: 'Watermark di bagian atas foto', value: 'top', groupValue: _watermarkPosition, onChanged: (value) => setState(() => _watermarkPosition = value!), icon: Icons.vertical_align_top),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('MINI MAP', Icons.map),
                _buildSwitchTile(title: 'Tampilkan Mini Map', subtitle: 'Menampilkan peta lokasi pada watermark', value: _showMiniMap, onChanged: (value) => setState(() => _showMiniMap = value), icon: Icons.map),
                if (_showMiniMap) ...[
                  _buildSliderTile(title: 'Zoom Level Mini Map', subtitle: 'Atur tingkat zoom peta (${_mapZoomLevel})', value: _mapZoomLevel.toDouble(), min: 10, max: 18, divisions: 8, onChanged: (value) => setState(() => _mapZoomLevel = value.toInt()), icon: Icons.zoom_in),
                  _buildRadioTile(title: 'Ukuran Kecil', subtitle: '250 x 150 pixel', value: 'small', groupValue: _mapSize, onChanged: (value) => setState(() => _mapSize = value!), icon: Icons.crop_square),
                  _buildRadioTile(title: 'Ukuran Sedang', subtitle: '350 x 180 pixel', value: 'medium', groupValue: _mapSize, onChanged: (value) => setState(() => _mapSize = value!), icon: Icons.crop_square),
                  _buildRadioTile(title: 'Ukuran Besar', subtitle: '450 x 200 pixel', value: 'large', groupValue: _mapSize, onChanged: (value) => setState(() => _mapSize = value!), icon: Icons.crop_square),
                ],
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('TAMPILAN', Icons.display_settings),
                _buildDropdownTile(title: 'Ukuran Font', subtitle: 'Pilih ukuran teks watermark', value: _fontSize, items: const ['small', 'normal', 'large'], onChanged: (value) => setState(() => _fontSize = value!), icon: Icons.text_fields),
                _buildDropdownTile(title: 'Mode Tema', subtitle: 'Pilih tema aplikasi', value: _themeMode, items: const ['light', 'dark', 'system'], onChanged: (value) => setState(() => _themeMode = value!), icon: Icons.brightness_4),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('KAMERA', Icons.camera_alt),
                _buildSliderTile(title: 'Kualitas Gambar', subtitle: 'Atur kualitas JPEG (${_imageQuality}%)', value: _imageQuality.toDouble(), min: 50, max: 100, divisions: 10, onChanged: (value) => setState(() => _imageQuality = value.toInt()), icon: Icons.image),
                _buildSwitchTile(title: 'Jaga Layar Tetap Nyala', subtitle: 'Mencegah layar mati saat menggunakan kamera', value: _keepScreenOn, onChanged: (value) => setState(() => _keepScreenOn = value), icon: Icons.screen_lock_portrait),
                _buildSwitchTile(title: 'GPS Akurasi Tinggi', subtitle: 'Menggunakan GPS dengan akurasi maksimal', value: _useHighAccuracy, onChanged: (value) => setState(() => _useHighAccuracy = value), icon: Icons.gps_fixed),
                _buildSwitchTile(title: 'Auto Save ke Galeri', subtitle: 'Menyimpan foto otomatis ke galeri setelah preview', value: _autoSave, onChanged: (value) => setState(() => _autoSave = value), icon: Icons.save_alt),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('PENYIMPANAN', Icons.storage),
                ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.cleaning_services, color: Colors.orange, size: 20)),
                  title: const Text('Bersihkan File Temporary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text('$_tempFileCount file (${_tempFileSize})', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  trailing: ElevatedButton(onPressed: () => _showClearCacheDialog(), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Hapus')),
                  onTap: () => _showClearCacheDialog(),
                ),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('TENTANG APLIKASI', Icons.info_outline),
                _buildInfoTile(title: 'TermulLog Premium', subtitle: 'Aplikasi dokumentasi dengan GPS watermark', icon: Icons.app_registration),
                _buildInfoTile(title: 'Versi', subtitle: '1.0.0 (Build 1)', icon: Icons.code),
                _buildInfoTile(title: 'Developer', subtitle: 'TermulLog Team', icon: Icons.developer_mode),
                _buildInfoTile(title: 'Sumber Data', subtitle: 'GPS: Geolocator • Cuaca: Open-Meteo • Peta: OpenStreetMap', icon: Icons.data_usage),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _showResetDialog(),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Reset ke Pengaturan Default'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade400, side: BorderSide(color: Colors.grey.shade700), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1F2E), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF00B8D4).withOpacity(0.3), width: 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.style, color: Color(0xFF00B8D4), size: 20)),
          const SizedBox(width: 12),
          const Text('Preview Watermark', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 16),
        Container(height: 200, width: double.infinity, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade800)), child: Center(child: _buildPreview())),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [Icon(icon, color: const Color(0xFF00B8D4), size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Color(0xFF00B8D4), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1))]),
    );
  }

  Widget _buildLayoutOption(WatermarkLayout layout) {
    final isSelected = _selectedLayout == layout;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: isSelected ? const Color(0xFF00B8D4).withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: isSelected ? Border.all(color: const Color(0xFF00B8D4).withOpacity(0.5), width: 1) : null),
      child: RadioListTile<WatermarkLayout>(
        title: Text(layout.displayName, style: TextStyle(color: Colors.white, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        subtitle: Text(layout.description, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        value: layout, groupValue: _selectedLayout, onChanged: (value) { if (value != null) setState(() => _selectedLayout = value); },
        activeColor: const Color(0xFF00B8D4), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  Widget _buildSwitchTile({required String title, required String subtitle, required bool value, required Function(bool) onChanged, required IconData icon}) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value, onChanged: onChanged, activeColor: const Color(0xFF00B8D4),
      secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF00B8D4), size: 20)),
    );
  }

  Widget _buildSliderTile({required String title, required String subtitle, required double value, required double min, required double max, required int divisions, required Function(double) onChanged, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF00B8D4), size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))])),
        ]),
        const SizedBox(height: 8),
        Slider(value: value, min: min, max: max, divisions: divisions, activeColor: const Color(0xFF00B8D4), inactiveColor: Colors.grey.shade700, label: value.toInt().toString(), onChanged: onChanged),
      ]),
    );
  }

  Widget _buildDropdownTile({required String title, required String subtitle, required String value, required List<String> items, required Function(String?) onChanged, required IconData icon}) {
    return ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF00B8D4), size: 20)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      trailing: DropdownButton<String>(value: value, dropdownColor: const Color(0xFF1A1F2E), style: const TextStyle(color: Color(0xFF00B8D4)), underline: Container(height: 0), items: items.map((item) => DropdownMenuItem(value: item, child: Text(item == 'small' ? 'Kecil' : item == 'normal' ? 'Normal' : item == 'large' ? 'Besar' : item == 'light' ? 'Terang' : item == 'dark' ? 'Gelap' : item == 'system' ? 'Sistem' : item))).toList(), onChanged: onChanged),
    );
  }

  Widget _buildRadioTile({required String title, required String subtitle, required String value, required String groupValue, required Function(String?) onChanged, required IconData icon}) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value, groupValue: groupValue, onChanged: onChanged, activeColor: const Color(0xFF00B8D4),
      secondary: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF00B8D4), size: 20)),
    );
  }

  Widget _buildInfoTile({required String title, required String subtitle, required IconData icon}) {
    return ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF00B8D4).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF00B8D4), size: 20)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
    );
  }

  Widget _buildPreview() {
    final now = DateTime.now();
    final String dateStr = _dateFormat == 'yyyy-MM-dd' ? DateFormat('yyyy-MM-dd').format(now)
        : _dateFormat == 'dd MMM yyyy' ? DateFormat('dd MMM yyyy', 'id').format(now)
        : _dateFormat == 'MMMM dd, yyyy' ? DateFormat('MMMM dd, yyyy', 'id').format(now)
        : DateFormat('dd/MM/yyyy').format(now);
    final String timeStr = _timeFormat == 'HH:mm' ? DateFormat('HH:mm').format(now)
        : _timeFormat == 'hh:mm:ss a' ? DateFormat('hh:mm:ss a', 'id').format(now)
        : DateFormat('HH:mm:ss').format(now);

    final double fontSize = _fontSize == 'small' ? 13 : _fontSize == 'large' ? 20 : 16;
    final double titleFontSize = fontSize + 4;
    final Color accent = const Color(0xFF00B8D4);
    final Color bgColor = Colors.black.withOpacity(_opacity);
    final Widget miniMapPlaceholder = _showMiniMap
        ? Container(
            width: _mapSize == 'small' ? 60 : _mapSize == 'large' ? 90 : 75,
            height: _mapSize == 'small' ? 60 : _mapSize == 'large' ? 90 : 75,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Center(child: Icon(Icons.map, color: Colors.grey, size: 28)),
          )
        : const SizedBox.shrink();

    switch (_selectedLayout) {
      case WatermarkLayout.cinematic:
        return Container(
          padding: const EdgeInsets.all(14),
          color: bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CINEMATIC', style: TextStyle(color: const Color(0xFFFFB432), fontWeight: FontWeight.bold, fontSize: titleFontSize)),
              const SizedBox(height: 8),
              Text(dateStr, style: TextStyle(color: Colors.white70, fontSize: fontSize)),
              Text(timeStr, style: TextStyle(color: accent, fontSize: fontSize + 4)),
              if (_showCoordinates)
                Text('-6.123456° / 106.123456°', style: TextStyle(color: Colors.white70, fontSize: fontSize - 2)),
              if (_showAccuracy)
                Text('Akurasi ±5 m', style: TextStyle(color: Colors.grey, fontSize: fontSize - 2)),
            ],
          ),
        );
      case WatermarkLayout.hud:
        return Container(
          padding: const EdgeInsets.all(14),
          color: bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$dateStr   $timeStr', style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_showCoordinates)
                Text('-6.123456, 106.123456', style: TextStyle(color: accent, fontSize: fontSize, fontWeight: FontWeight.w600)),
              if (_showAccuracy)
                Text('±5 m', style: TextStyle(color: Colors.grey, fontSize: fontSize - 2)),
            ],
          ),
        );
      case WatermarkLayout.polaroid:
        return Container(
          color: const Color(0xFFF8F5EB),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 90,
                width: double.infinity,
                color: Colors.grey.shade400,
                child: const Center(child: Icon(Icons.image, color: Colors.grey, size: 36)),
              ),
              const SizedBox(height: 10),
              Text(dateStr, style: TextStyle(color: Colors.black87, fontSize: fontSize, fontWeight: FontWeight.w500)),
              if (_showCoordinates)
                Text('-6.123, 106.123', style: TextStyle(color: Colors.black54, fontSize: fontSize - 2)),
            ],
          ),
        );
      case WatermarkLayout.documentary:
        return Container(
          padding: const EdgeInsets.all(12),
          color: bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DOCUMENTARY', style: TextStyle(color: accent, fontSize: titleFontSize, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$dateStr  $timeStr', style: TextStyle(color: Colors.white70, fontSize: fontSize)),
              if (_showCoordinates)
                Text('-6.123456°  106.123456°', style: TextStyle(color: Colors.white54, fontSize: fontSize - 2)),
            ],
          ),
        );
      case WatermarkLayout.leica:
        return Container(
          padding: const EdgeInsets.all(14),
          color: bgColor,
          child: Row(
            children: [
              const Icon(Icons.circle, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(dateStr, style: TextStyle(color: Colors.white, fontSize: fontSize - 2)),
                    Text(timeStr, style: TextStyle(color: Colors.white, fontSize: fontSize)),
                    if (_showCoordinates)
                      Text('-6.123456°  106.123456°', style: TextStyle(color: Colors.white70, fontSize: fontSize - 3)),
                  ],
                ),
              ),
            ],
          ),
        );
      case WatermarkLayout.survey:
        return Container(
          padding: const EdgeInsets.all(12),
          color: bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                color: const Color(0xFF00A86B),
                child: Text('SURVEY DATA', style: TextStyle(color: Colors.black, fontSize: fontSize - 2, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text('DATE : $dateStr', style: TextStyle(color: Colors.white70, fontSize: fontSize - 2)),
              Text('TIME : $timeStr', style: TextStyle(color: Colors.white70, fontSize: fontSize - 2)),
              if (_showCoordinates)
                Text('LAT : -6.123456  LON : 106.123456', style: TextStyle(color: Colors.grey, fontSize: fontSize - 3)),
              if (_showAccuracy)
                Text('ACC : ±5 m', style: TextStyle(color: Colors.grey, fontSize: fontSize - 3)),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Color _getPreviewTextColor() {
    switch (_selectedLayout) {
      case WatermarkLayout.cinematic: return const Color(0xFFFFB432);
      case WatermarkLayout.hud: return const Color(0xFF00B8D4);
      case WatermarkLayout.polaroid: return Colors.black87;
      case WatermarkLayout.documentary: return const Color(0xFF00B8D4);
      case WatermarkLayout.leica: return Colors.white;
      case WatermarkLayout.survey: return const Color(0xFF00A86B);
      default: return const Color(0xFF00B8D4);
    }
  }

  void _showResetDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF1A1F2E), title: const Text('Reset Pengaturan', style: TextStyle(color: Colors.white)), content: const Text('Apakah Anda yakin ingin mereset semua pengaturan watermark ke nilai default?', style: TextStyle(color: Colors.grey)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))), ElevatedButton(onPressed: () { Navigator.pop(context); _resetToDefault(); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B8D4), foregroundColor: Colors.black), child: const Text('Reset'))]));
  }

  void _showClearCacheDialog() {
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF1A1F2E), title: const Text('Bersihkan Cache', style: TextStyle(color: Colors.white)), content: Text('Hapus $_tempFileCount file temporary (${_tempFileSize})?\n\nFile ini adalah foto sementara yang belum disimpan ke galeri. Foto yang sudah disimpan tidak akan terhapus.', style: TextStyle(color: Colors.grey.shade400)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))), ElevatedButton(onPressed: () { Navigator.pop(context); _clearTempFiles(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white), child: const Text('Hapus Sekarang'))]));
  }
}
