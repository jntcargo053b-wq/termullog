// lib/screens/settings_screen.dart
// TOTAL REBUILD – Settings bersih, hanya yang relevan untuk timestamp app

import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../services/settings_cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  WatermarkLayout _layout = WatermarkLayout.podCorporate;
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  double _opacity = 0.88;
  bool _showBorder = true;
  String _dateFormat = 'dd MMM yyyy';
  String _timeFormat = 'HH:mm:ss';
  int _imageQuality = 92;
  bool _useHighAccuracy = true;
  bool _autoSave = false;
  String _appName = 'TermulLog';
  Uint8List? _customLogoBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _layout = await SettingsCache.layout;
    _showWeather = await SettingsCache.showWeather;
    _showAccuracy = await SettingsCache.showAccuracy;
    _showAddress = await SettingsCache.showAddress;
    _showCoordinates = await SettingsCache.showCoordinates;
    _opacity = await SettingsCache.opacity;
    _showBorder = await SettingsCache.showBorder;
    _dateFormat = await SettingsCache.dateFormat;
    _timeFormat = await SettingsCache.timeFormat;
    _imageQuality = await SettingsCache.imageQuality;
    _useHighAccuracy = await SettingsCache.useHighAccuracy;
    _autoSave = await SettingsCache.autoSave;
    _appName = await SettingsCache.appName;
    _customLogoBytes = await SettingsCache.getCustomLogoBytes();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await SettingsCache.setLayout(_layout);
    await SettingsCache.setShowWeather(_showWeather);
    await SettingsCache.setShowAccuracy(_showAccuracy);
    await SettingsCache.setShowAddress(_showAddress);
    await SettingsCache.setShowCoordinates(_showCoordinates);
    await SettingsCache.setOpacity(_opacity);
    await SettingsCache.setShowBorder(_showBorder);
    await SettingsCache.setDateFormat(_dateFormat);
    await SettingsCache.setTimeFormat(_timeFormat);
    await SettingsCache.setImageQuality(_imageQuality);
    await SettingsCache.setUseHighAccuracy(_useHighAccuracy);
    await SettingsCache.setAutoSave(_autoSave);
    await SettingsCache.setAppName(_appName);
    await SettingsCache.setCustomLogoBytes(_customLogoBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B16),
        title: const Text('Pengaturan',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          TextButton(
            onPressed: () async {
              await _save();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Simpan',
                style: TextStyle(color: Color(0xFF1E90FF), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E90FF)))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _sectionHeader('Gaya Watermark'),
                _layoutPicker(),

                _sectionHeader('Branding'),
                _appNameField(),
                _logoPicker(),

                _sectionHeader('Informasi yang Ditampilkan'),
                _toggle('Koordinat GPS', _showCoordinates,
                    (v) => setState(() => _showCoordinates = v),
                    icon: Icons.gps_fixed),
                _toggle('Akurasi GPS', _showAccuracy,
                    (v) => setState(() => _showAccuracy = v),
                    icon: Icons.radar),
                _toggle('Alamat', _showAddress,
                    (v) => setState(() => _showAddress = v),
                    icon: Icons.location_on_outlined),
                _toggle('Cuaca', _showWeather,
                    (v) => setState(() => _showWeather = v),
                    icon: Icons.wb_cloudy_outlined),

                _sectionHeader('Tampilan'),
                _toggle('Border kartu', _showBorder,
                    (v) => setState(() => _showBorder = v),
                    icon: Icons.border_outer),
                _slider('Transparansi', _opacity, 0.4, 1.0,
                    (v) => setState(() => _opacity = v)),
                _slider('Kualitas JPEG', _imageQuality.toDouble(), 60, 100,
                    (v) => setState(() => _imageQuality = v.round()),
                    suffix: '%'),

                _sectionHeader('Format'),
                _formatPicker('Format Tanggal', _dateFormat, [
                  'dd MMM yyyy',
                  'dd/MM/yyyy',
                  'yyyy-MM-dd',
                  'EEEE, dd MMM yyyy',
                ], (v) => setState(() => _dateFormat = v)),
                _formatPicker('Format Waktu', _timeFormat, [
                  'HH:mm:ss',
                  'HH:mm',
                  'hh:mm a',
                ], (v) => setState(() => _timeFormat = v)),

                _sectionHeader('GPS'),
                _toggle('Akurasi Tinggi (GPS + Network)', _useHighAccuracy,
                    (v) => setState(() => _useHighAccuracy = v),
                    icon: Icons.satellite_alt),

                _sectionHeader('Lainnya'),
                _toggle('Simpan Otomatis ke Galeri', _autoSave,
                    (v) => setState(() => _autoSave = v),
                    icon: Icons.save_alt),

                _sectionHeader('Penyimpanan'),
                _cacheInfo(),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              color: Color(0xFF1E90FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2)),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChange,
      {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        secondary:
            icon != null ? Icon(icon, color: const Color(0xFF3A4570), size: 20) : null,
        value: value,
        onChanged: onChange,
        activeColor: const Color(0xFF1E90FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChange,
      {String suffix = ''}) {
    final display = suffix == '%'
        ? '${value.round()}$suffix'
        : value.toStringAsFixed(2);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 14))),
              Text(display,
                  style: const TextStyle(
                      color: Color(0xFF1E90FF), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChange,
            activeColor: const Color(0xFF1E90FF),
            inactiveColor: const Color(0xFF1A2540),
          ),
        ],
      ),
    );
  }

  Widget _formatPicker(
      String label, String current, List<String> options, ValueChanged<String> onChange) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 14))),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current,
              dropdownColor: const Color(0xFF0D1325),
              style: const TextStyle(color: Color(0xFF1E90FF), fontSize: 13),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) { if (v != null) onChange(v); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _layoutPicker() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: WatermarkLayout.values.map((l) {
          final sel = l == _layout;
          return GestureDetector(
            onTap: () => setState(() => _layout = l),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF1E90FF).withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: sel ? const Color(0xFF1E90FF) : const Color(0xFF1A2540),
                ),
              ),
              child: Text(l.displayName,
                  style: TextStyle(
                      color: sel ? const Color(0xFF1E90FF) : Colors.white38,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _appNameField() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: Color(0xFF3A4570), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: _appName,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Nama pada Watermark',
                labelStyle: TextStyle(color: Color(0xFF3A4570), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              maxLength: 30,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  Text('$currentLength/$maxLength',
                      style: const TextStyle(color: Color(0xFF3A4570), fontSize: 11)),
              onChanged: (v) => setState(() => _appName = v.trim().isEmpty ? 'TermulLog' : v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoPicker() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.image_outlined, color: Color(0xFF3A4570), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Logo Watermark',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  _customLogoBytes != null
                      ? 'Logo custom terpasang'
                      : 'Menggunakan logo default',
                  style: const TextStyle(color: Color(0xFF3A4570), fontSize: 11),
                ),
              ],
            ),
          ),
          if (_customLogoBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(_customLogoBytes!, width: 48, height: 32, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFE63946), size: 20),
              onPressed: () => setState(() => _customLogoBytes = null),
              tooltip: 'Hapus logo',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload_outlined, size: 16),
            label: Text(_customLogoBytes != null ? 'Ganti' : 'Pilih'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1E90FF),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 200,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _customLogoBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih logo: $e')),
        );
      }
    }
  }

    Widget _cacheInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1325),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: const Icon(Icons.delete_sweep_outlined,
            color: Color(0xFFE63946), size: 20),
        title: const Text('Bersihkan Cache Histori',
            style: TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: const Text('Hapus semua foto dari penyimpanan internal',
            style: TextStyle(color: Color(0xFF3A4570), fontSize: 11)),
        onTap: _clearCache,
      ),
    );
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A0E1A),
        title: const Text('Bersihkan cache?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Foto di penyimpanan internal akan dihapus (galeri tidak terpengaruh).',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus', style: TextStyle(color: Color(0xFFE63946)))),
        ],
      ),
    );
    if (ok == true) {
      try {
        final dir = Directory(
            '${(await getApplicationDocumentsDirectory()).path}/history');
        if (await dir.exists()) await dir.delete(recursive: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cache dibersihkan')));
        }
      } catch (_) {}
    }
  }
}
