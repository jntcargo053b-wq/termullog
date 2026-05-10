import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

// ============================================================
// SETTINGS SERVICE
// ============================================================

class SettingsService {
  // Shared Preferences Keys
  static const String _keyWatermarkLayout = 'watermark_layout';
  static const String _keyShowWeather = 'show_weather';
  static const String _keyShowAccuracy = 'show_accuracy';
  static const String _keyShowAddress = 'show_address';
  static const String _keyShowCoordinates = 'show_coordinates';
  static const String _keyWatermarkPosition = 'watermark_position';
  static const String _keyDateFormat = 'date_format';
  static const String _keyTimeFormat = 'time_format';
  static const String _keyOpacity = 'opacity';
  static const String _keyShowMiniMap = 'show_mini_map';
  static const String _keyMapZoomLevel = 'map_zoom_level';
  static const String _keyMapSize = 'map_size';
  static const String _keyFontSize = 'font_size';
  static const String _keyShowBorder = 'show_border';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyKeepScreenOn = 'keep_screen_on';
  static const String _keyAutoSave = 'auto_save';
  static const String _keyImageQuality = 'image_quality';
  static const String _keyUseHighAccuracy = 'use_high_accuracy';

  // ============================================================
  // WATERMARK LAYOUT
  // ============================================================

  /// Mendapatkan layout watermark yang dipilih
  static Future<WatermarkLayout> getWatermarkLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyWatermarkLayout) ?? WatermarkLayout.modern.index;
    return WatermarkLayout.values[index];
  }

  /// Menyimpan layout watermark yang dipilih
  static Future<void> setWatermarkLayout(WatermarkLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyWatermarkLayout, layout.index);
  }

  // ============================================================
  // INFORMASI YANG DITAMPILKAN
  // ============================================================

  /// Mendapatkan status tampilkan cuaca
  static Future<bool> getShowWeather() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowWeather) ?? true;
  }

  /// Menyimpan status tampilkan cuaca
  static Future<void> setShowWeather(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowWeather, show);
  }

  /// Mendapatkan status tampilkan akurasi GPS
  static Future<bool> getShowAccuracy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowAccuracy) ?? true;
  }

  /// Menyimpan status tampilkan akurasi GPS
  static Future<void> setShowAccuracy(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowAccuracy, show);
  }

  /// Mendapatkan status tampilkan alamat
  static Future<bool> getShowAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowAddress) ?? true;
  }

  /// Menyimpan status tampilkan alamat
  static Future<void> setShowAddress(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowAddress, show);
  }

  /// Mendapatkan status tampilkan koordinat
  static Future<bool> getShowCoordinates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowCoordinates) ?? true;
  }

  /// Menyimpan status tampilkan koordinat
  static Future<void> setShowCoordinates(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowCoordinates, show);
  }

  // ============================================================
  // POSISI WATERMARK
  // ============================================================

  /// Mendapatkan posisi watermark (top/bottom)
  static Future<String> getWatermarkPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWatermarkPosition) ?? 'bottom';
  }

  /// Menyimpan posisi watermark (top/bottom)
  static Future<void> setWatermarkPosition(String position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWatermarkPosition, position);
  }

  // ============================================================
  // FORMAT TANGGAL & WAKTU
  // ============================================================

  /// Mendapatkan format tanggal
  static Future<String> getDateFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDateFormat) ?? 'dd/MM/yyyy';
  }

  /// Menyimpan format tanggal
  static Future<void> setDateFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDateFormat, format);
  }

  /// Mendapatkan format waktu
  static Future<String> getTimeFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTimeFormat) ?? 'HH:mm:ss';
  }

  /// Menyimpan format waktu
  static Future<void> setTimeFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimeFormat, format);
  }

  // ============================================================
  // TRANSPARANSI & TAMPILAN
  // ============================================================

  /// Mendapatkan nilai opacity background
  static Future<double> getOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyOpacity) ?? 0.85;
  }

  /// Menyimpan nilai opacity background
  static Future<void> setOpacity(double opacity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyOpacity, opacity.clamp(0.0, 1.0));
  }

  /// Mendapatkan status tampilkan border
  static Future<bool> getShowBorder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowBorder) ?? true;
  }

  /// Menyimpan status tampilkan border
  static Future<void> setShowBorder(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowBorder, show);
  }

  // ============================================================
  // MINI MAP
  // ============================================================

  /// Mendapatkan status tampilkan mini map
  static Future<bool> getShowMiniMap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowMiniMap) ?? true;
  }

  /// Menyimpan status tampilkan mini map
  static Future<void> setShowMiniMap(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowMiniMap, show);
  }

  /// Mendapatkan zoom level untuk mini map
  static Future<int> getMapZoomLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyMapZoomLevel) ?? 16;
  }

  /// Menyimpan zoom level untuk mini map
  static Future<void> setMapZoomLevel(int zoom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMapZoomLevel, zoom.clamp(10, 18));
  }

  /// Mendapatkan ukuran mini map
  static Future<String> getMapSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMapSize) ?? 'medium';
  }

  /// Menyimpan ukuran mini map (small/medium/large)
  static Future<void> setMapSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMapSize, size);
  }

  // ============================================================
  // FONT & TEKS
  // ============================================================

  /// Mendapatkan ukuran font
  static Future<String> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFontSize) ?? 'normal';
  }

  /// Menyimpan ukuran font (small/normal/large)
  static Future<void> setFontSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontSize, size);
  }

  // ============================================================
  // KAMERA & KUALITAS
  // ============================================================

  /// Mendapatkan kualitas gambar
  static Future<int> getImageQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyImageQuality) ?? 90;
  }

  /// Menyimpan kualitas gambar (50-100)
  static Future<void> setImageQuality(int quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageQuality, quality.clamp(50, 100));
  }

  /// Mendapatkan status keep screen on
  static Future<bool> getKeepScreenOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyKeepScreenOn) ?? true;
  }

  /// Menyimpan status keep screen on
  static Future<void> setKeepScreenOn(bool keep) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepScreenOn, keep);
  }

  /// Mendapatkan status auto save ke galeri
  static Future<bool> getAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSave) ?? false;
  }

  /// Menyimpan status auto save
  static Future<void> setAutoSave(bool auto) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSave, auto);
  }

  /// Mendapatkan status penggunaan GPS high accuracy
  static Future<bool> getUseHighAccuracy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseHighAccuracy) ?? true;
  }

  /// Menyimpan status penggunaan GPS high accuracy
  static Future<void> setUseHighAccuracy(bool high) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseHighAccuracy, high);
  }

  // ============================================================
  // TEMA APLIKASI
  // ============================================================

  /// Mendapatkan mode tema (light/dark/system)
  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'dark';
  }

  /// Menyimpan mode tema
  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  // ============================================================
  // RESET SETTINGS
  // ============================================================

  /// Mereset semua pengaturan ke nilai default
  static Future<void> resetAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Reset semua keys
    await prefs.setInt(_keyWatermarkLayout, WatermarkLayout.modern.index);
    await prefs.setBool(_keyShowWeather, true);
    await prefs.setBool(_keyShowAccuracy, true);
    await prefs.setBool(_keyShowAddress, true);
    await prefs.setBool(_keyShowCoordinates, true);
    await prefs.setString(_keyWatermarkPosition, 'bottom');
    await prefs.setString(_keyDateFormat, 'dd/MM/yyyy');
    await prefs.setString(_keyTimeFormat, 'HH:mm:ss');
    await prefs.setDouble(_keyOpacity, 0.85);
    await prefs.setBool(_keyShowMiniMap, true);
    await prefs.setInt(_keyMapZoomLevel, 16);
    await prefs.setString(_keyMapSize, 'medium');
    await prefs.setString(_keyFontSize, 'normal');
    await prefs.setBool(_keyShowBorder, true);
    await prefs.setString(_keyThemeMode, 'dark');
    await prefs.setBool(_keyKeepScreenOn, true);
    await prefs.setBool(_keyAutoSave, false);
    await prefs.setInt(_keyImageQuality, 90);
    await prefs.setBool(_keyUseHighAccuracy, true);
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Mendapatkan ukuran map berdasarkan setting
  static Future<Map<String, int>> getMapDimensions() async {
    final size = await getMapSize();
    switch (size) {
      case 'small':
        return {'width': 250, 'height': 150};
      case 'large':
        return {'width': 450, 'height': 200};
      case 'medium':
      default:
        return {'width': 350, 'height': 180};
    }
  }

  /// Mendapatkan faktor skala font
  static Future<double> getFontScale() async {
    final size = await getFontSize();
    switch (size) {
      case 'small':
        return 0.85;
      case 'large':
        return 1.15;
      case 'normal':
      default:
        return 1.0;
    }
  }
}
