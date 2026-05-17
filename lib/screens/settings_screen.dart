// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../core/constants.dart';
import '../services/settings_service.dart';
import '../services/settings_cache.dart';

// Warna tema — const agar tidak dialokasikan ulang setiap build
const _kAccent = Color(0xFF00B8D4);
const _kSurface = Color(0xFF1A1F2E);
const _kBackground = Color(0xFF0A0E1A);

// Label terjemahan untuk dropdown
const _kLabelMap = <String, String>{
  'small': 'Kecil',
  'normal': 'Normal',
  'large': 'Besar',
  'light': 'Terang',
  'dark': 'Gelap',
  'system': 'Sistem',
};

String _label(String value) => _kLabelMap[value] ?? value;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Watermark ─────────────────────────────────────────────────────────────
  WatermarkLayout _selectedLayout = WatermarkLayout.modern;
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  String _watermarkPosition = 'bottom';
  double _opacity = 0.85;
  bool _showBorder = true;

  // ── Format ────────────────────────────────────────────────────────────────
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = 'HH:mm:ss';

  // ── Mini Map ──────────────────────────────────────────────────────────────
  bool _showMiniMap = true;
  int _mapZoomLevel = 16;
  String _mapSize = 'medium';

  // ── Display ───────────────────────────────────────────────────────────────
  String _fontSize = 'normal';
  String _themeMode = 'dark';

  // ── Camera ────────────────────────────────────────────────────────────────
  int _imageQuality = 90;
  bool _keepScreenOn = true;
  bool _useHighAccuracy = true;
  bool _autoSave = false;

  // ── Cache ─────────────────────────────────────────────────────────────────
  int _tempFileCount = 0;
  String _tempFileSize = '0 KB';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheInfo();
  }

  // Semua getter independen — jalankan paralel
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      SettingsService.getWatermarkLayout(),    // 0
      SettingsService.getShowWeather(),         // 1
      SettingsService.getShowAccuracy(),        // 2
      SettingsService.getShowAddress(),         // 3
      SettingsService.getShowCoordinates(),     // 4
      SettingsService.getWatermarkPosition(),   // 5
      SettingsService.getOpacity(),             // 6
      SettingsService.getShowBorder(),          // 7
      SettingsService.getDateFormat(),          // 8
      SettingsService.getTimeFormat(),          // 9
      SettingsService.getShowMiniMap(),         // 10
      SettingsService.getMapZoomLevel(),        // 11
      SettingsService.getMapSize(),             // 12
      SettingsService.getFontSize(),            // 13
      SettingsService.getThemeMode(),           // 14
      SettingsService.getImageQuality(),        // 15
      SettingsService.getKeepScreenOn(),        // 16
      SettingsService.getUseHighAccuracy(),     // 17
      SettingsService.getAutoSave(),            // 18
    ]);

    setState(() {
      _selectedLayout     = results[0] as WatermarkLayout;
      _showWeather        = results[1] as bool;
      _showAccuracy       = results[2] as bool;
      _showAddress        = results[3] as bool;
      _showCoordinates    = results[4] as bool;
      _watermarkPosition  = results[5] as String;
      _opacity            = results[6] as double;
      _showBorder         = results[7] as bool;
      _dateFormat         = results[8] as String;
      _timeFormat         = results[9] as String;
      _showMiniMap        = results[10] as bool;
      _mapZoomLevel       = results[11] as int;
      _mapSize            = results[12] as String;
      _fontSize           = results[13] as String;
      _themeMode          = results[14] as String;
      _imageQuality       = results[15] as int;
      _keepScreenOn       = results[16] as bool;
      _useHighAccuracy    = results[17] as bool;
      _autoSave           = results[18] as bool;
      _isLoading          = false;
    });
  }

  // Semua setter independen — jalankan paralel
  Future<void> _saveSettings() async {
    await Future.wait([
      SettingsService.setWatermarkLayout(_selectedLayout),
      SettingsService.setShowWeather(_showWeather),
      SettingsService.setShowAccuracy(_showAccuracy),
      SettingsService.setShowAddress(_showAddress),
      SettingsService.setShowCoordinates(_showCoordinates),
      SettingsService.setWatermarkPosition(_watermarkPosition),
      SettingsService.setOpacity(_opacity),
      SettingsService.setShowBorder(_showBorder),
      SettingsService.setDateFormat(_dateFormat),
      SettingsService.setTimeFormat(_timeFormat),
      SettingsService.setShowMiniMap(_showMiniMap),
      SettingsService.setMapZoomLevel(_mapZoomLevel),
      SettingsService.setMapSize(_mapSize),
      SettingsService.setFontSize(_fontSize),
      SettingsService.setThemeMode(_themeMode),
      SettingsService.setImageQuality(_imageQuality),
      SettingsService.setKeepScreenOn(_keepScreenOn),
      SettingsService.setUseHighAccuracy(_useHighAccuracy),
      SettingsService.setAutoSave(_autoSave),
    ]);

    SettingsCache.invalidate();
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
          backgroundColor: _kSurface,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _applyKeepScreenOn() {
    // Gunakan wakelock plugin jika tersedia.
    // SystemUiMode tidak mengontrol sleep — ini placeholder.
    // TODO: ganti dengan WakelockPlus.toggle(on: _keepScreenOn)
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
          backgroundColor: _kSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Gunakan async list() agar tidak memblokir UI thread
  Future<void> _loadCacheInfo() async {
    try {
      final dir = await getTemporaryDirectory();
      final entities = await dir.list().toList();
      final files = entities
          .whereType<File>()
          .where((f) => path.basename(f.path).startsWith('termullog_'))
          .toList();

      // Hitung ukuran paralel
      final sizes = await Future.wait(files.map((f) => f.length()));
      final totalSize = sizes.fold<int>(0, (sum, s) => sum + s);

      final sizeStr = totalSize < 1024
          ? '$totalSize B'
          : totalSize < 1024 * 1024
              ? '${(totalSize / 1024).toStringAsFixed(1)} KB'
              : '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';

      if (mounted) {
        setState(() {
          _tempFileCount = files.length;
          _tempFileSize = sizeStr;
        });
      }
    } catch (e) {
      debugPrint('Load cache info error: $e');
    }
  }

  Future<void> _clearTempFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      final entities = await dir.list().toList();
      final files = entities
          .whereType<File>()
          .where((f) => path.basename(f.path).startsWith('termullog_'))
          .toList();

      int deletedCount = 0;
      for (final file in files) {
        try {
          await file.delete();
          deletedCount++;
        } catch (e) {
          debugPrint('Failed to delete: ${file.path} — $e');
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

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dividerColor = Colors.grey.shade800;
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('Pengaturan',
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _kSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: _kAccent),
            onPressed: _saveSettings,
            tooltip: 'Simpan Pengaturan',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              children: [
                _buildPreviewCard(),
                const SizedBox(height: 8),
                _buildSectionHeader('GAYA TAMPILAN', Icons.style),
                ...WatermarkLayout.values.map(_buildLayoutOption),
                _buildSliderTile(
                  title: 'Transparansi Background',
                  subtitle: 'Atur kegelapan background watermark',
                  value: _opacity,
                  min: 0.3,
                  max: 1.0,
                  divisions: 14,
                  onChanged: (v) => setState(() => _opacity = v),
                  icon: Icons.opacity,
                ),
                _buildSwitchTile(
                  title: 'Tampilkan Border',
                  subtitle: 'Menampilkan border di sekitar watermark',
                  value: _showBorder,
                  onChanged: (v) => setState(() => _showBorder = v),
                  icon: Icons.border_style,
                ),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader(
                    'INFORMASI YANG DITAMPILKAN', Icons.info_outline),
                _buildSwitchTile(
                    title: 'Tampilkan Cuaca',
                    subtitle: 'Menampilkan informasi cuaca di watermark',
                    value: _showWeather,
                    onChanged: (v) => setState(() => _showWeather = v),
                    icon: Icons.wb_sunny),
                _buildSwitchTile(
                    title: 'Tampilkan Akurasi GPS',
                    subtitle: 'Menampilkan tingkat akurasi GPS dalam meter',
                    value: _showAccuracy,
                    onChanged: (v) => setState(() => _showAccuracy = v),
                    icon: Icons.gps_fixed),
                _buildSwitchTile(
                    title: 'Tampilkan Alamat',
                    subtitle: 'Menampilkan alamat lengkap lokasi',
                    value: _showAddress,
                    onChanged: (v) => setState(() => _showAddress = v),
                    icon: Icons.location_on),
                _buildSwitchTile(
                    title: 'Tampilkan Koordinat',
                    subtitle: 'Menampilkan koordinat GPS',
                    value: _showCoordinates,
                    onChanged: (v) => setState(() => _showCoordinates = v),
                    icon: Icons.map),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader(
                    'FORMAT TANGGAL & WAKTU', Icons.calendar_today),
                _buildDropdownTile(
                    title: 'Format Tanggal',
                    subtitle: 'Pilih format tampilan tanggal',
                    value: _dateFormat,
                    items: const [
                      'dd/MM/yyyy',
                      'yyyy-MM-dd',
                      'dd MMM yyyy',
                      'MMMM dd, yyyy',
                      'dd MMMM yyyy'
                    ],
                    onChanged: (v) => setState(() => _dateFormat = v!),
                    icon: Icons.calendar_today),
                _buildDropdownTile(
                    title: 'Format Waktu',
                    subtitle: 'Pilih format tampilan waktu',
                    value: _timeFormat,
                    items: const [
                      'HH:mm:ss',
                      'HH:mm',
                      'hh:mm:ss a',
                      'hh:mm a'
                    ],
                    onChanged: (v) => setState(() => _timeFormat = v!),
                    icon: Icons.access_time),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader(
                    'POSISI WATERMARK', Icons.vertical_align_center),
                _buildRadioTile(
                    title: 'Bawah',
                    subtitle: 'Watermark di bagian bawah foto',
                    value: 'bottom',
                    groupValue: _watermarkPosition,
                    onChanged: (v) =>
                        setState(() => _watermarkPosition = v!),
                    icon: Icons.vertical_align_bottom),
                _buildRadioTile(
                    title: 'Atas',
                    subtitle: 'Watermark di bagian atas foto',
                    value: 'top',
                    groupValue: _watermarkPosition,
                    onChanged: (v) =>
                        setState(() => _watermarkPosition = v!),
                    icon: Icons.vertical_align_top),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('MINI MAP', Icons.map),
                _buildSwitchTile(
                    title: 'Tampilkan Mini Map',
                    subtitle: 'Menampilkan peta lokasi pada watermark',
                    value: _showMiniMap,
                    onChanged: (v) => setState(() => _showMiniMap = v),
                    icon: Icons.map),
                if (_showMiniMap) ...[
                  _buildSliderTile(
                    title: 'Zoom Level Mini Map',
                    subtitle: 'Atur tingkat zoom peta ($_mapZoomLevel)',
                    value: _mapZoomLevel.toDouble(),
                    min: 10,
                    max: 18,
                    divisions: 8,
                    onChanged: (v) =>
                        setState(() => _mapZoomLevel = v.toInt()),
                    icon: Icons.zoom_in,
                  ),
                  _buildRadioTile(
                      title: 'Ukuran Kecil',
                      subtitle: '250 x 150 pixel',
                      value: 'small',
                      groupValue: _mapSize,
                      onChanged: (v) => setState(() => _mapSize = v!),
                      icon: Icons.crop_square),
                  _buildRadioTile(
                      title: 'Ukuran Sedang',
                      subtitle: '350 x 180 pixel',
                      value: 'medium',
                      groupValue: _mapSize,
                      onChanged: (v) => setState(() => _mapSize = v!),
                      icon: Icons.crop_square),
                  _buildRadioTile(
                      title: 'Ukuran Besar',
                      subtitle: '450 x 200 pixel',
                      value: 'large',
                      groupValue: _mapSize,
                      onChanged: (v) => setState(() => _mapSize = v!),
                      icon: Icons.crop_square),
                ],
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('TAMPILAN', Icons.display_settings),
                _buildDropdownTile(
                    title: 'Ukuran Font',
                    subtitle: 'Pilih ukuran teks watermark',
                    value: _fontSize,
                    items: const ['small', 'normal', 'large'],
                    onChanged: (v) => setState(() => _fontSize = v!),
                    icon: Icons.text_fields),
                _buildDropdownTile(
                    title: 'Mode Tema',
                    subtitle: 'Pilih tema aplikasi',
                    value: _themeMode,
                    items: const ['light', 'dark', 'system'],
                    onChanged: (v) => setState(() => _themeMode = v!),
                    icon: Icons.brightness_4),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('KAMERA', Icons.camera_alt),
                _buildSliderTile(
                  title: 'Kualitas Gambar',
                  subtitle: 'Atur kualitas JPEG ($_imageQuality%)',
                  value: _imageQuality.toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 10,
                  onChanged: (v) =>
                      setState(() => _imageQuality = v.toInt()),
                  icon: Icons.image,
                ),
                _buildSwitchTile(
                    title: 'Jaga Layar Tetap Nyala',
                    subtitle: 'Mencegah layar mati saat menggunakan kamera',
                    value: _keepScreenOn,
                    onChanged: (v) => setState(() => _keepScreenOn = v),
                    icon: Icons.screen_lock_portrait),
                _buildSwitchTile(
                    title: 'GPS Akurasi Tinggi',
                    subtitle: 'Menggunakan GPS dengan akurasi maksimal',
                    value: _useHighAccuracy,
                    onChanged: (v) =>
                        setState(() => _useHighAccuracy = v),
                    icon: Icons.gps_fixed),
                _buildSwitchTile(
                    title: 'Auto Save ke Galeri',
                    subtitle:
                        'Menyimpan foto otomatis ke galeri setelah preview',
                    value: _autoSave,
                    onChanged: (v) => setState(() => _autoSave = v),
                    icon: Icons.save_alt),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('PENYIMPANAN', Icons.storage),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kAccent.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cleaning_services,
                        color: Colors.orange, size: 20),
                  ),
                  title: const Text('Bersihkan File Temporary',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '$_tempFileCount file ($_tempFileSize)',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
                  trailing: ElevatedButton(
                    onPressed: _showClearCacheDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Hapus'),
                  ),
                  onTap: _showClearCacheDialog,
                ),
                Divider(color: dividerColor, height: 24, thickness: 1),
                _buildSectionHeader('TENTANG APLIKASI', Icons.info_outline),
                _buildInfoTile(
                    title: 'TermulLog Premium',
                    subtitle:
                        'Aplikasi dokumentasi dengan GPS watermark',
                    icon: Icons.app_registration),
                _buildInfoTile(
                    title: 'Versi',
                    subtitle: '1.0.0 (Build 1)',
                    icon: Icons.code),
                _buildInfoTile(
                    title: 'Developer',
                    subtitle: 'TermulLog Team',
                    icon: Icons.developer_mode),
                _buildInfoTile(
                    title: 'Sumber Data',
                    subtitle:
                        'GPS: Geolocator • Cuaca: Open-Meteo • Peta: OpenStreetMap',
                    icon: Icons.data_usage),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: _showResetDialog,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Reset ke Pengaturan Default'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade400,
                      side: BorderSide(color: Colors.grey.shade700),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  // ── WIDGET HELPERS ─────────────────────────────────────────────────────────

  Widget _buildPreviewCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent.withAlpha(76), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withAlpha(51),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.style, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Preview Watermark',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Center(child: _buildPreview()),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Icon(icon, color: _kAccent, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: _kAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1)),
      ]),
    );
  }

  Widget _buildLayoutOption(WatermarkLayout layout) {
    final isSelected = _selectedLayout == layout;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? _kAccent.withAlpha(38) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: _kAccent.withAlpha(127), width: 1)
            : null,
      ),
      child: RadioListTile<WatermarkLayout>(
        title: Text(layout.displayName,
            style: TextStyle(
                color: Colors.white,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal)),
        subtitle: Text(layout.description,
            style:
                TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        value: layout,
        groupValue: _selectedLayout,
        onChanged: (v) {
          if (v != null) setState(() => _selectedLayout = v);
        },
        activeColor: _kAccent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return SwitchListTile(
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeColor: _kAccent,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kAccent.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: _kAccent,
            inactiveColor: Colors.grey.shade700,
            label: value.toInt().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownTile({
    required String title,
    required String subtitle,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kAccent.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: _kSurface,
        style: const TextStyle(color: _kAccent),
        underline: const SizedBox.shrink(),
        items: items
            .map((item) => DropdownMenuItem(
                value: item, child: Text(_label(item))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return RadioListTile<String>(
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: _kAccent,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kAccent.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kAccent.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
    );
  }

  // ── PREVIEW ────────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final textColor = _getPreviewTextColor();

    String dateStr = '15/05/2024';
    switch (_dateFormat) {
      case 'yyyy-MM-dd':    dateStr = '2024-05-15'; break;
      case 'dd MMM yyyy':   dateStr = '15 Mei 2024'; break;
      case 'MMMM dd, yyyy': dateStr = 'Mei 15, 2024'; break;
      case 'dd MMMM yyyy':  dateStr = '15 Mei 2024'; break;
    }

    String timeStr = '14:30:25';
    switch (_timeFormat) {
      case 'HH:mm':      timeStr = '14:30'; break;
      case 'hh:mm:ss a': timeStr = '02:30:25 PM'; break;
      case 'hh:mm a':    timeStr = '02:30 PM'; break;
    }

    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 3, width: 40, color: _kAccent),
              const SizedBox(height: 8),
              Text('TERMULOG',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$dateStr  $timeStr',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showCoordinates)
                const Text('-6.123456, 106.123456',
                    style: TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showAccuracy)
                Text('±5 m',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 9)),
              if (_showAddress)
                Text('Jl. Contoh No. 123',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 8)),
            ],
          ),
        );

      case WatermarkLayout.modern:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 3, height: 20, color: _kAccent),
                const SizedBox(width: 8),
                Text('📍 TERMULOG',
                    style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Text('$timeStr  •  $dateStr',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showCoordinates)
                const Text('🌐 -6.123456°, 106.123456°',
                    style: TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showAccuracy)
                Text('🎯 Akurasi: ±5 m',
                    style: TextStyle(color: textColor, fontSize: 9)),
              if (_showWeather)
                Text('🌤️ Cerah 32°C',
                    style: TextStyle(color: textColor, fontSize: 9)),
            ],
          ),
        );

      case WatermarkLayout.elegant:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TERMULOG',
                  style: TextStyle(
                      color: Color(0xFFFFB432),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(dateStr,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 9)),
              Text(timeStr,
                  style: TextStyle(color: textColor, fontSize: 9)),
              if (_showCoordinates)
                const Text('-6.123456°\n106.123456°',
                    style: TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showAccuracy)
                Text('Akurasi ±5 m',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 9)),
            ],
          ),
        );

      case WatermarkLayout.professional:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                color: _kAccent,
                padding: const EdgeInsets.symmetric(
                    vertical: 4, horizontal: 8),
                child: const Text('TERMULOG DOCUMENT',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text('DATE : $dateStr',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 8)),
              Text('TIME : $timeStr',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 8)),
              if (_showCoordinates)
                Text('LAT : -6.123456\nLON : 106.123456',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 8)),
              if (_showAccuracy)
                Text('ACC : ±5 m',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 8)),
              if (_showAddress)
                Text('ADDR : Jl. Contoh No. 123',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 7)),
            ],
          ),
        );

      case WatermarkLayout.semiTransparent:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$dateStr   $timeStr',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              if (_showCoordinates)
                Text('-6.123456, 106.123456',
                    style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              if (_showAccuracy)
                Text('±5 m',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 10)),
            ],
          ),
        );

      case WatermarkLayout.gpsCard:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
                bottom: BorderSide(color: _kAccent, width: 3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$dateStr  $timeStr',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10)),
              const SizedBox(height: 6),
              const Text('-6.123456°N  106.123456°E',
                  style: TextStyle(color: _kAccent, fontSize: 10)),
              if (_showAccuracy)
                Text('±5 m',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 9)),
              const SizedBox(height: 4),
              Text('Jl. Contoh No. 123, Kec. Contoh',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 8),
                  maxLines: 2),
            ],
          ),
        );

      case WatermarkLayout.polaroid:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5EB),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 80,
                width: double.infinity,
                color: Colors.grey.shade400,
                child: const Center(
                    child:
                        Icon(Icons.image, color: Colors.grey, size: 32)),
              ),
              const SizedBox(height: 8),
              Text(dateStr,
                  style: const TextStyle(
                      color: Colors.black87, fontSize: 10)),
              const Text('-6.123, 106.123',
                  style:
                      TextStyle(color: Colors.black54, fontSize: 9)),
            ],
          ),
        );

      case WatermarkLayout.sidePanel:
        return Row(children: [
          Container(
            width: 50,
            height: 120,
            color: const Color(0xFF0A0F28),
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('14',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Text('30',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Text('25',
                    style: TextStyle(
                        color: _kAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('15',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
                const Text('Mei',
                    style: TextStyle(color: _kAccent, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 120,
              color: Colors.grey.shade800,
              child: const Center(
                  child:
                      Icon(Icons.image, color: Colors.grey, size: 40)),
            ),
          ),
        ]);

      // cinematicV2 dan timeMarkStyle tampil identik
      case WatermarkLayout.cinematicV2:
      case WatermarkLayout.timeMarkStyle:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timeStr,
                  style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dateStr,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10)),
            ],
          ),
        );
    }
  }

  Color _getPreviewTextColor() {
    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return Colors.white;
      case WatermarkLayout.professional:
        return Colors.white70;
      case WatermarkLayout.modern:
      case WatermarkLayout.elegant:
      case WatermarkLayout.gpsCard:
      case WatermarkLayout.polaroid:
      case WatermarkLayout.sidePanel:
      case WatermarkLayout.semiTransparent:
      case WatermarkLayout.cinematicV2:
      case WatermarkLayout.timeMarkStyle:
        return _kAccent;
    }
  }

  // ── DIALOGS ────────────────────────────────────────────────────────────────

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('Reset Pengaturan',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Apakah Anda yakin ingin mereset semua pengaturan watermark ke nilai default?',
            style: TextStyle(color: Colors.grey)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToDefault();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.black),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('Bersihkan Cache',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'Hapus $_tempFileCount file temporary ($_tempFileSize)?\n\n'
            'File ini adalah foto sementara yang belum disimpan ke galeri. '
            'Foto yang sudah disimpan tidak akan terhapus.',
            style: TextStyle(color: Colors.grey.shade400)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearTempFiles();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white),
            child: const Text('Hapus Sekarang'),
          ),
        ],
      ),
    );
  }
}
