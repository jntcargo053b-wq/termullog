import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/settings_service.dart';

// ============================================================
// SETTINGS SCREEN
// ============================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  WatermarkLayout _selectedLayout = WatermarkLayout.modern;
  bool _showWeather = true;
  bool _showAccuracy = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  String _watermarkPosition = 'bottom';
  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = 'HH:mm:ss';
  double _opacity = 0.85;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    final layout = await SettingsService.getWatermarkLayout();
    final showWeather = await SettingsService.getShowWeather();
    final showAccuracy = await SettingsService.getShowAccuracy();
    final showAddress = await SettingsService.getShowAddress();
    final showCoordinates = await SettingsService.getShowCoordinates();
    final position = await SettingsService.getWatermarkPosition();
    final dateFormat = await SettingsService.getDateFormat();
    final timeFormat = await SettingsService.getTimeFormat();
    final opacity = await SettingsService.getOpacity();
    
    setState(() {
      _selectedLayout = layout;
      _showWeather = showWeather;
      _showAccuracy = showAccuracy;
      _showAddress = showAddress;
      _showCoordinates = showCoordinates;
      _watermarkPosition = position;
      _dateFormat = dateFormat;
      _timeFormat = timeFormat;
      _opacity = opacity;
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
    await SettingsService.setDateFormat(_dateFormat);
    await SettingsService.setTimeFormat(_timeFormat);
    await SettingsService.setOpacity(_opacity);
    
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

  Future<void> _resetToDefault() async {
    setState(() {
      _selectedLayout = WatermarkLayout.modern;
      _showWeather = true;
      _showAccuracy = true;
      _showAddress = true;
      _showCoordinates = true;
      _watermarkPosition = 'bottom';
      _dateFormat = 'dd/MM/yyyy';
      _timeFormat = 'HH:mm:ss';
      _opacity = 0.85;
    });
    await _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Colors.grey.shade800;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text(
          'Pengaturan',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00B8D4),
              ),
            )
          : ListView(
              children: [
                // Preview Card
                _buildPreviewCard(),
                
                const SizedBox(height: 8),
                
                // Section: Gaya Tampilan
                _buildSectionHeader('GAYA TAMPILAN', Icons.style),
                ...WatermarkLayout.values.map((layout) => _buildLayoutOption(layout)),
                
                Divider(color: dividerColor, height: 24, thickness: 1),
                
                // Section: Informasi yang Ditampilkan
                _buildSectionHeader('INFORMASI YANG DITAMPILKAN', Icons.info_outline),
                
                _buildSwitchTile(
                  title: 'Tampilkan Cuaca',
                  subtitle: 'Menampilkan informasi cuaca di watermark',
                  value: _showWeather,
                  onChanged: (value) => setState(() => _showWeather = value),
                  icon: Icons.wb_sunny,
                ),
                
                _buildSwitchTile(
                  title: 'Tampilkan Akurasi GPS',
                  subtitle: 'Menampilkan tingkat akurasi GPS dalam meter',
                  value: _showAccuracy,
                  onChanged: (value) => setState(() => _showAccuracy = value),
                  icon: Icons.gps_fixed,
                ),
                
                _buildSwitchTile(
                  title: 'Tampilkan Alamat',
                  subtitle: 'Menampilkan alamat lengkap lokasi',
                  value: _showAddress,
                  onChanged: (value) => setState(() => _showAddress = value),
                  icon: Icons.location_on,
                ),
                
                _buildSwitchTile(
                  title: 'Tampilkan Koordinat',
                  subtitle: 'Menampilkan koordinat GPS (Latitude, Longitude)',
                  value: _showCoordinates,
                  onChanged: (value) => setState(() => _showCoordinates = value),
                  icon: Icons.map,
                ),
                
                Divider(color: dividerColor, height: 24, thickness: 1),
                
                // Section: Format Tanggal & Waktu
                _buildSectionHeader('FORMAT TANGGAL & WAKTU', Icons.calendar_today),
                
                _buildDropdownTile(
                  title: 'Format Tanggal',
                  subtitle: 'Pilih format tampilan tanggal',
                  value: _dateFormat,
                  items: const [
                    'dd/MM/yyyy',
                    'yyyy-MM-dd',
                    'dd MMM yyyy',
                    'MMMM dd, yyyy',
                    'dd MMMM yyyy',
                  ],
                  onChanged: (value) => setState(() => _dateFormat = value!),
                  icon: Icons.calendar_today,
                ),
                
                _buildDropdownTile(
                  title: 'Format Waktu',
                  subtitle: 'Pilih format tampilan waktu',
                  value: _timeFormat,
                  items: const [
                    'HH:mm:ss',
                    'HH:mm',
                    'hh:mm:ss a',
                    'hh:mm a',
                  ],
                  onChanged: (value) => setState(() => _timeFormat = value!),
                  icon: Icons.access_time,
                ),
                
                Divider(color: dividerColor, height: 24, thickness: 1),
                
                // Section: Posisi Watermark
                _buildSectionHeader('POSISI WATERMARK', Icons.vertical_align_center),
                
                _buildRadioTile(
                  title: 'Bawah',
                  subtitle: 'Watermark di bagian bawah foto',
                  value: 'bottom',
                  groupValue: _watermarkPosition,
                  onChanged: (value) => setState(() => _watermarkPosition = value!),
                  icon: Icons.vertical_align_bottom,
                ),
                
                _buildRadioTile(
                  title: 'Atas',
                  subtitle: 'Watermark di bagian atas foto',
                  value: 'top',
                  groupValue: _watermarkPosition,
                  onChanged: (value) => setState(() => _watermarkPosition = value!),
                  icon: Icons.vertical_align_top,
                ),
                
                Divider(color: dividerColor, height: 24, thickness: 1),
                
                // Section: Opacity
                _buildSectionHeader('TRANSPARANSI', Icons.opacity),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.opacity, color: Color(0xFF00B8D4), size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Opacity: ${(_opacity * 100).toInt()}%',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Slider(
                        value: _opacity,
                        min: 0.3,
                        max: 1.0,
                        divisions: 14,
                        activeColor: const Color(0xFF00B8D4),
                        inactiveColor: Colors.grey.shade700,
                        label: '${(_opacity * 100).toInt()}%',
                        onChanged: (value) => setState(() => _opacity = value),
                      ),
                      Text(
                        'Semakin rendah nilai, semakin transparan background watermark',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                
                Divider(color: dividerColor, height: 24, thickness: 1),
                
                // Section: Info Aplikasi
                _buildSectionHeader('TENTANG APLIKASI', Icons.info_outline),
                
                _buildInfoTile(
                  title: 'TermulLog Premium',
                  subtitle: 'Aplikasi dokumentasi dengan GPS watermark',
                  icon: Icons.app_registration,
                ),
                
                _buildInfoTile(
                  title: 'Versi',
                  subtitle: '1.0.0 (Build 1)',
                  icon: Icons.code,
                ),
                
                _buildInfoTile(
                  title: 'Developer',
                  subtitle: 'TermulLog Team',
                  icon: Icons.developer_mode,
                ),
                
                const SizedBox(height: 16),
                
                // Tombol Reset
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _showResetDialog(),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Reset ke Pengaturan Default'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade400,
                      side: BorderSide(color: Colors.grey.shade700),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00B8D4).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B8D4).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.watermark,
                  color: Color(0xFF00B8D4),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Preview Watermark',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Center(
              child: _buildPreview(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00B8D4), size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF00B8D4),
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutOption(WatermarkLayout layout) {
    final isSelected = _selectedLayout == layout;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected 
            ? const Color(0xFF00B8D4).withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: const Color(0xFF00B8D4).withOpacity(0.5), width: 1)
            : null,
      ),
      child: RadioListTile<WatermarkLayout>(
        title: Text(
          layout.displayName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          layout.description,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
        value: layout,
        groupValue: _selectedLayout,
        onChanged: (value) {
          if (value != null) {
            setState(() => _selectedLayout = value);
          }
        },
        activeColor: const Color(0xFF00B8D4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF00B8D4),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF00B8D4).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00B8D4), size: 20),
      ),
    );
  }

  Widget _buildDropdownTile({
    required String title,
    required String subtitle,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF00B8D4).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00B8D4), size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: const Color(0xFF1A1F2E),
        style: const TextStyle(color: Color(0xFF00B8D4)),
        underline: Container(height: 0),
        items: items.map((item) {
          return DropdownMenuItem(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: const Color(0xFF00B8D4),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF00B8D4).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00B8D4), size: 20),
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
          color: const Color(0xFF00B8D4).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF00B8D4), size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
    );
  }

  Widget _buildPreview() {
    final bgColor = Colors.black;
    final textColor = _getPreviewTextColor();
    
    // Get sample date and time based on format
    final now = DateTime.now();
    String dateStr = '';
    String timeStr = '';
    
    if (_dateFormat == 'dd/MM/yyyy') dateStr = '15/05/2024';
    else if (_dateFormat == 'yyyy-MM-dd') dateStr = '2024-05-15';
    else if (_dateFormat == 'dd MMM yyyy') dateStr = '15 Mei 2024';
    else if (_dateFormat == 'MMMM dd, yyyy') dateStr = 'Mei 15, 2024';
    else dateStr = '15 Mei 2024';
    
    if (_timeFormat == 'HH:mm:ss') timeStr = '14:30:25';
    else if (_timeFormat == 'HH:mm') timeStr = '14:30';
    else if (_timeFormat == 'hh:mm:ss a') timeStr = '02:30:25 PM';
    else timeStr = '02:30 PM';
    
    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 3, width: 40, color: const Color(0xFF00B8D4)),
              const SizedBox(height: 8),
              Text('TERMULOG', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$dateStr  $timeStr', style: TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showCoordinates) ...[
                const SizedBox(height: 4),
                Text('-6.123456, 106.123456', style: TextStyle(color: Colors.white70, fontSize: 9)),
              ],
              if (_showAccuracy) ...[
                const SizedBox(height: 4),
                Text('±5 m', style: TextStyle(color: Colors.grey.shade500, fontSize: 9)),
              ],
              if (_showAddress) ...[
                const SizedBox(height: 4),
                Text('Jl. Contoh No. 123', style: TextStyle(color: Colors.grey.shade500, fontSize: 8)),
              ],
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
                Container(width: 3, height: 20, color: const Color(0xFF00B8D4)),
                const SizedBox(width: 8),
                Text('📍 TERMULOG', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Text('$timeStr  •  $dateStr', style: TextStyle(color: Colors.white70, fontSize: 9)),
              if (_showCoordinates) ...[
                const SizedBox(height: 4),
                Text('🌐 -6.123456°, 106.123456°', style: TextStyle(color: Colors.white70, fontSize: 9)),
              ],
              if (_showAccuracy) ...[
                const SizedBox(height: 4),
                Text('🎯 Akurasi: ±5 m', style: TextStyle(color: textColor, fontSize: 9)),
              ],
              if (_showWeather) ...[
                const SizedBox(height: 4),
                Text('🌤️ Cerah 32°C', style: TextStyle(color: textColor, fontSize: 9)),
              ],
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
              Text('TERMULOG', style: TextStyle(color: const Color(0xFFFFB432), fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(dateStr, style: TextStyle(color: Colors.white70, fontSize: 9)),
              Text(timeStr, style: TextStyle(color: textColor, fontSize: 9)),
              if (_showCoordinates) ...[
                const SizedBox(height: 4),
                Text('-6.123456°', style: TextStyle(color: Colors.white70, fontSize: 9)),
                Text('106.123456°', style: TextStyle(color: Colors.white70, fontSize: 9)),
              ],
              if (_showAccuracy) ...[
                const SizedBox(height: 4),
                Text('Akurasi ±5 m', style: TextStyle(color: Colors.grey.shade500, fontSize: 9)),
              ],
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
                color: const Color(0xFF00B8D4),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: const Text('TERMULOG DOCUMENT', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text('DATE : $dateStr', style: TextStyle(color: Colors.white70, fontSize: 8)),
              Text('TIME : $timeStr', style: TextStyle(color: Colors.white70, fontSize: 8)),
              if (_showCoordinates) ...[
                const SizedBox(height: 4),
                Text('LAT : -6.123456', style: TextStyle(color: Colors.grey.shade500, fontSize: 8)),
                Text('LON : 106.123456', style: TextStyle(color: Colors.grey.shade500, fontSize: 8)),
              ],
              if (_showAccuracy) ...[
                Text('ACC : ±5 m', style: TextStyle(color: Colors.grey.shade500, fontSize: 8)),
              ],
              if (_showAddress) ...[
                const SizedBox(height: 4),
                Text('ADDR : Jl. Contoh No. 123', style: TextStyle(color: Colors.grey.shade500, fontSize: 7)),
              ],
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
              Text('$dateStr   $timeStr', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              if (_showCoordinates) ...[
                Text('-6.123456, 106.123456', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
              ],
              if (_showAccuracy) ...[
                Text('±5 m', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
              ],
            ],
          ),
        );
    }
  }

  Color _getPreviewTextColor() {
    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return Colors.white;
      case WatermarkLayout.modern:
        return const Color(0xFF00B8D4);
      case WatermarkLayout.elegant:
        return const Color(0xFF00B8D4);
      case WatermarkLayout.professional:
        return Colors.white70;
      case WatermarkLayout.semiTransparent:
        return const Color(0xFF00B8D4);
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Reset Pengaturan', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Apakah Anda yakin ingin mereset semua pengaturan watermark ke nilai default?',
          style: TextStyle(color: Colors.grey),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToDefault();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B8D4),
              foregroundColor: Colors.black,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
