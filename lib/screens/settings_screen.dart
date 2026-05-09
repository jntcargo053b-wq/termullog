import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  WatermarkLayout _selectedLayout = WatermarkLayout.modern;
  bool _showWeather = true;
  bool _showAccuracy = true;
  String _watermarkPosition = 'bottom';
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final layout = await SettingsService.getWatermarkLayout();
    final showWeather = await SettingsService.getShowWeather();
    final showAccuracy = await SettingsService.getShowAccuracy();
    final position = await SettingsService.getWatermarkPosition();
    
    setState(() {
      _selectedLayout = layout;
      _showWeather = showWeather;
      _showAccuracy = showAccuracy;
      _watermarkPosition = position;
    });
  }
  
  Future<void> _saveSettings() async {
    await SettingsService.setWatermarkLayout(_selectedLayout);
    await SettingsService.setShowWeather(_showWeather);
    await SettingsService.setShowAccuracy(_showAccuracy);
    await SettingsService.setWatermarkPosition(_watermarkPosition);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan disimpan')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final dividerColor = Colors.grey.shade800;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Watermark'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        children: [
          // Preview Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview Watermark',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: Center(
                    child: Text(
                      _getPreviewText(),
                      style: TextStyle(
                        color: _getPreviewColor(),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Layout Style
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Gaya Tampilan',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...WatermarkLayout.values.map((layout) => RadioListTile<WatermarkLayout>(
            title: Text(layout.displayName, style: const TextStyle(color: Colors.white)),
            subtitle: Text(layout.description, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            value: layout,
            groupValue: _selectedLayout,
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedLayout = value);
              }
            },
            activeColor: const Color(0xFF00B8D4),
          )),
          
          Divider(color: dividerColor),
          
          // Opsi Tambahan
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Informasi yang Ditampilkan',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Tampilkan Cuaca', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Menampilkan informasi cuaca di watermark'),
            value: _showWeather,
            onChanged: (value) {
              setState(() => _showWeather = value);
            },
            activeColor: const Color(0xFF00B8D4),
          ),
          SwitchListTile(
            title: const Text('Tampilkan Akurasi', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Menampilkan tingkat akurasi GPS'),
            value: _showAccuracy,
            onChanged: (value) {
              setState(() => _showAccuracy = value);
            },
            activeColor: const Color(0xFF00B8D4),
          ),
          
          Divider(color: dividerColor),
          
          // Posisi Watermark
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Posisi Watermark',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          RadioListTile<String>(
            title: const Text('Bawah', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Watermark di bagian bawah foto'),
            value: 'bottom',
            groupValue: _watermarkPosition,
            onChanged: (value) {
              if (value != null) {
                setState(() => _watermarkPosition = value);
              }
            },
            activeColor: const Color(0xFF00B8D4),
          ),
          RadioListTile<String>(
            title: const Text('Atas', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Watermark di bagian atas foto'),
            value: 'top',
            groupValue: _watermarkPosition,
            onChanged: (value) {
              if (value != null) {
                setState(() => _watermarkPosition = value);
              }
            },
            activeColor: const Color(0xFF00B8D4),
          ),
          
          const SizedBox(height: 20),
          
          // Tombol Reset
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () async {
                setState(() {
                  _selectedLayout = WatermarkLayout.modern;
                  _showWeather = true;
                  _showAccuracy = true;
                  _watermarkPosition = 'bottom';
                });
                await _saveSettings();
              },
              icon: const Icon(Icons.restore),
              label: const Text('Reset ke Default'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getPreviewText() {
    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return 'TERMULOG\n15/05/2024 14:30\n-6.12345, 106.12345\nAkurasi: ±5m';
      case WatermarkLayout.modern:
        return '📍 TERMULOG\n14:30 • 15 Mei 2024\n🌐 -6.12345°, 106.12345°';
      case WatermarkLayout.elegant:
        return '📍 TERMULOG\n15 Mei 2024\n🌐 -6.12345°, 106.12345°';
      case WatermarkLayout.professional:
        return 'TERMULOG\n15/05/2024 14:30\nLat: -6.12345 Lon: 106.12345\nAccuracy: ±5m';
    }
  }
  
  Color _getPreviewColor() {
    switch (_selectedLayout) {
      case WatermarkLayout.minimal:
        return Colors.white;
      case WatermarkLayout.modern:
        return const Color(0xFF00B8D4);
      case WatermarkLayout.elegant:
        return const Color(0xFF00B8D4);
      case WatermarkLayout.professional:
        return Colors.white70;
    }
  }
}
