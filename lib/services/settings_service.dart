// lib/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class SettingsService {
  static const String _keyWatermarkLayout = 'watermark_layout_type'; // ← GANTI key (pakai _type)
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

  // Singleton cache untuk SharedPreferences (hindari panggilan berulang)
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _instance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ============================================================
  // WATERMARK LAYOUT — simpan pakai typeString (string), BUKAN .index atau .name
  // ============================================================
  static Future<WatermarkLayout> getWatermarkLayout() async {
    final prefs = await _instance();
    
    // Coba baca dari key baru (typeString)
    String? savedType = prefs.getString(_keyWatermarkLayout);
    
    // Fallback: jika tidak ada, coba baca dari key lama (watermark_layout) untuk migrasi
    if (savedType == null) {
      final oldIndex = prefs.getInt('watermark_layout');
      if (oldIndex != null) {
        // Migrasi dari index lama ke typeString
        final oldLayout = WatermarkLayout.fromIndex(oldIndex);
        savedType = oldLayout.typeString;
        // Simpan ke key baru
        await prefs.setString(_keyWatermarkLayout, savedType);
        // Hapus key lama
        await prefs.remove('watermark_layout');
      }
    }
    
    // Fallback: jika masih null, coba baca dari .name (migrasi dari name)
    if (savedType == null) {
      final oldName = prefs.getString('watermark_layout');
      if (oldName != null) {
        // Cari enum dari name
        final found = WatermarkLayout.values.cast<WatermarkLayout?>().firstWhere(
          (e) => e?.name == oldName,
          orElse: () => null,
        );
        if (found != null) {
          savedType = found.typeString;
          await prefs.setString(_keyWatermarkLayout, savedType);
          await prefs.remove('watermark_layout');
        }
      }
    }
    
    // Default ke 'modern' jika semua gagal
    return WatermarkLayout.fromTypeString(savedType ?? 'modern');
  }

  static Future<void> setWatermarkLayout(WatermarkLayout layout) async {
    final prefs = await _instance();
    await prefs.setString(_keyWatermarkLayout, layout.typeString); // ← simpan typeString
  }

  // ============================================================
  // INFORMASI YANG DITAMPILKAN
  // ============================================================
  static Future<bool> getShowWeather() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowWeather) ?? true;
  }
  static Future<void> setShowWeather(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowWeather, show);
  }

  static Future<bool> getShowAccuracy() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowAccuracy) ?? true;
  }
  static Future<void> setShowAccuracy(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowAccuracy, show);
  }

  static Future<bool> getShowAddress() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowAddress) ?? true;
  }
  static Future<void> setShowAddress(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowAddress, show);
  }

  static Future<bool> getShowCoordinates() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowCoordinates) ?? true;
  }
  static Future<void> setShowCoordinates(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowCoordinates, show);
  }

  // ============================================================
  // POSISI WATERMARK (dengan validasi)
  // ============================================================
  static const _validPositions = {'top', 'bottom'};

  static Future<String> getWatermarkPosition() async {
    final prefs = await _instance();
    return prefs.getString(_keyWatermarkPosition) ?? 'bottom';
  }

  static Future<void> setWatermarkPosition(String position) async {
    final prefs = await _instance();
    if (!_validPositions.contains(position)) {
      position = 'bottom';
    }
    await prefs.setString(_keyWatermarkPosition, position);
  }

  // ============================================================
  // FORMAT TANGGAL & WAKTU
  // ============================================================
  static Future<String> getDateFormat() async {
    final prefs = await _instance();
    return prefs.getString(_keyDateFormat) ?? 'dd/MM/yyyy';
  }
  static Future<void> setDateFormat(String format) async {
    final prefs = await _instance();
    await prefs.setString(_keyDateFormat, format);
  }

  static Future<String> getTimeFormat() async {
    final prefs = await _instance();
    return prefs.getString(_keyTimeFormat) ?? 'HH:mm:ss';
  }
  static Future<void> setTimeFormat(String format) async {
    final prefs = await _instance();
    await prefs.setString(_keyTimeFormat, format);
  }

  // ============================================================
  // TRANSPARANSI & TAMPILAN
  // ============================================================
  static Future<double> getOpacity() async {
    final prefs = await _instance();
    return prefs.getDouble(_keyOpacity) ?? 0.85;
  }
  static Future<void> setOpacity(double opacity) async {
    final prefs = await _instance();
    await prefs.setDouble(_keyOpacity, opacity.clamp(0.0, 1.0));
  }

  static Future<bool> getShowBorder() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowBorder) ?? true;
  }
  static Future<void> setShowBorder(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowBorder, show);
  }

  // ============================================================
  // MINI MAP
  // ============================================================
  static Future<bool> getShowMiniMap() async {
    final prefs = await _instance();
    return prefs.getBool(_keyShowMiniMap) ?? true;
  }
  static Future<void> setShowMiniMap(bool show) async {
    final prefs = await _instance();
    await prefs.setBool(_keyShowMiniMap, show);
  }

  static Future<int> getMapZoomLevel() async {
    final prefs = await _instance();
    return prefs.getInt(_keyMapZoomLevel) ?? 16;
  }
  static Future<void> setMapZoomLevel(int zoom) async {
    final prefs = await _instance();
    await prefs.setInt(_keyMapZoomLevel, zoom.clamp(10, 18));
  }

  static const _validMapSizes = {'small', 'medium', 'large'};

  static Future<String> getMapSize() async {
    final prefs = await _instance();
    return prefs.getString(_keyMapSize) ?? 'medium';
  }
  static Future<void> setMapSize(String size) async {
    final prefs = await _instance();
    if (!_validMapSizes.contains(size)) {
      size = 'medium';
    }
    await prefs.setString(_keyMapSize, size);
  }

  // ============================================================
  // FONT & TEKS (dengan validasi)
  // ============================================================
  static const _validFontSizes = {'small', 'normal', 'large'};

  static Future<String> getFontSize() async {
    final prefs = await _instance();
    return prefs.getString(_keyFontSize) ?? 'normal';
  }
  static Future<void> setFontSize(String size) async {
    final prefs = await _instance();
    if (!_validFontSizes.contains(size)) {
      size = 'normal';
    }
    await prefs.setString(_keyFontSize, size);
  }

  // ============================================================
  // TEMA APLIKASI (dengan validasi)
  // ============================================================
  static const _validThemeModes = {'light', 'dark', 'system'};

  static Future<String> getThemeMode() async {
    final prefs = await _instance();
    return prefs.getString(_keyThemeMode) ?? 'dark';
  }
  static Future<void> setThemeMode(String mode) async {
    final prefs = await _instance();
    if (!_validThemeModes.contains(mode)) {
      mode = 'dark';
    }
    await prefs.setString(_keyThemeMode, mode);
  }

  // ============================================================
  // KAMERA & KUALITAS
  // ============================================================
  static Future<int> getImageQuality() async {
    final prefs = await _instance();
    return prefs.getInt(_keyImageQuality) ?? 90;
  }
  static Future<void> setImageQuality(int quality) async {
    final prefs = await _instance();
    await prefs.setInt(_keyImageQuality, quality.clamp(50, 100));
  }

  static Future<bool> getKeepScreenOn() async {
    final prefs = await _instance();
    return prefs.getBool(_keyKeepScreenOn) ?? true;
  }
  static Future<void> setKeepScreenOn(bool keep) async {
    final prefs = await _instance();
    await prefs.setBool(_keyKeepScreenOn, keep);
  }

  static Future<bool> getAutoSave() async {
    final prefs = await _instance();
    return prefs.getBool(_keyAutoSave) ?? false;
  }
  static Future<void> setAutoSave(bool auto) async {
    final prefs = await _instance();
    await prefs.setBool(_keyAutoSave, auto);
  }

  static Future<bool> getUseHighAccuracy() async {
    final prefs = await _instance();
    return prefs.getBool(_keyUseHighAccuracy) ?? true;
  }
  static Future<void> setUseHighAccuracy(bool high) async {
    final prefs = await _instance();
    await prefs.setBool(_keyUseHighAccuracy, high);
  }

  // ============================================================
  // RESET SETTINGS (pakai Future.wait untuk performa)
  // ============================================================
  static Future<void> resetAllSettings() async {
    final prefs = await _instance();
    await Future.wait([
      prefs.setString(_keyWatermarkLayout, WatermarkLayout.modern.typeString), // ← pakai typeString
      prefs.setBool(_keyShowWeather, true),
      prefs.setBool(_keyShowAccuracy, true),
      prefs.setBool(_keyShowAddress, true),
      prefs.setBool(_keyShowCoordinates, true),
      prefs.setString(_keyWatermarkPosition, 'bottom'),
      prefs.setString(_keyDateFormat, 'dd/MM/yyyy'),
      prefs.setString(_keyTimeFormat, 'HH:mm:ss'),
      prefs.setDouble(_keyOpacity, 0.85),
      prefs.setBool(_keyShowMiniMap, true),
      prefs.setInt(_keyMapZoomLevel, 16),
      prefs.setString(_keyMapSize, 'medium'),
      prefs.setString(_keyFontSize, 'normal'),
      prefs.setBool(_keyShowBorder, true),
      prefs.setString(_keyThemeMode, 'dark'),
      prefs.setBool(_keyKeepScreenOn, true),
      prefs.setBool(_keyAutoSave, false),
      prefs.setInt(_keyImageQuality, 90),
      prefs.setBool(_keyUseHighAccuracy, true),
    ]);
  }

  // ============================================================
  // MIGRASI DATA LAMA KE FORMAT BARU
  // ============================================================
  static Future<void> migrateOldSettings() async {
    final prefs = await _instance();
    
    // Migrasi watermark_layout dari index ke typeString
    if (prefs.containsKey('watermark_layout')) {
      final oldIndex = prefs.getInt('watermark_layout');
      if (oldIndex != null) {
        final layout = WatermarkLayout.fromIndex(oldIndex);
        await prefs.setString(_keyWatermarkLayout, layout.typeString);
        await prefs.remove('watermark_layout');
        debugPrint('✅ Migrated watermark_layout from index $oldIndex to ${layout.typeString}');
      }
    }
    
    // Migrasi dari .name jika ada
    if (prefs.containsKey('watermark_layout_name')) {
      final oldName = prefs.getString('watermark_layout_name');
      if (oldName != null) {
        final found = WatermarkLayout.values.cast<WatermarkLayout?>().firstWhere(
          (e) => e?.name == oldName,
          orElse: () => null,
        );
        if (found != null) {
          await prefs.setString(_keyWatermarkLayout, found.typeString);
          await prefs.remove('watermark_layout_name');
          debugPrint('✅ Migrated watermark_layout_name from $oldName to ${found.typeString}');
        }
      }
    }
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================
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

// Tambahkan import untuk debugPrint
import 'package:flutter/foundation.dart' show debugPrint;
