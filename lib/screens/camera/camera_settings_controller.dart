import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../services/settings_cache.dart';

class CaptureSettings {
  final bool showWeather, showAccuracy, showAddress, showCoordinates, showBorder;
  final double opacity;
  final WatermarkLayout layout;
  final bool showMiniMap;
  final int mapZoomLevel;
  final String dateFormat, timeFormat, fontSize, appName;
  final Uint8List? customLogoBytes;
  const CaptureSettings({
    required this.showWeather,
    required this.showAccuracy,
    required this.showAddress,
    required this.showCoordinates,
    required this.opacity,
    required this.showBorder,
    required this.layout,
    required this.showMiniMap,
    required this.mapZoomLevel,
    required this.dateFormat,
    required this.timeFormat,
    required this.fontSize,
    required this.appName,
    required this.customLogoBytes,
  });
}

class CameraSettingsController extends ChangeNotifier {
  bool showWeather = true;
  bool showAccuracy = true;
  bool showAddress = true;
  bool showCoordinates = true;
  double opacity = 0.88;
  bool showBorder = true;
  WatermarkLayout layout = WatermarkLayout.podCorporate;
  bool showMiniMap = false;
  int mapZoomLevel = 15;
  String dateFormat = 'dd/MM/yyyy';
  String timeFormat = 'HH:mm:ss';
  String fontSize = 'normal';
  String appName = 'TermulLog';
  Uint8List? customLogoBytes;
  ui.Image? customLogoImage;

  bool isLoading = true;

  final ValueNotifier<WatermarkLayout> layoutNotifier =
      ValueNotifier(WatermarkLayout.podCorporate);

  CameraSettingsController();

  Future<void> load() async {
    isLoading = true;
    notifyListeners();

    await SettingsCache.preload();

    showWeather = await SettingsCache.showWeather;
    showAccuracy = await SettingsCache.showAccuracy;
    showAddress = await SettingsCache.showAddress;
    showCoordinates = await SettingsCache.showCoordinates;
    opacity = await SettingsCache.opacity;
    showBorder = await SettingsCache.showBorder;
    layout = await SettingsCache.layout;
    layoutNotifier.value = layout;
    showMiniMap = await SettingsCache.showMiniMap;
    mapZoomLevel = await SettingsCache.mapZoomLevel;
    dateFormat = await SettingsCache.dateFormat;
    timeFormat = await SettingsCache.timeFormat;

    final fontSizeDouble = await SettingsCache.fontSize;
    fontSize = fontSizeDouble <= 13 ? 'small' : fontSizeDouble >= 20 ? 'large' : 'normal';

    appName = await SettingsCache.appName;
    customLogoBytes = await SettingsCache.getCustomLogoBytes();

    if (customLogoBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(customLogoBytes!);
        final frame = await codec.getNextFrame();
        customLogoImage = frame.image;
      } catch (_) {
        customLogoImage = null;
      }
    } else {
      customLogoImage = null;
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> reload() async {
    SettingsCache.invalidate();
    await load();
  }

  Future<void> setLayout(WatermarkLayout newLayout) async {
    layout = newLayout;
    layoutNotifier.value = newLayout;
    await SettingsCache.setLayout(newLayout);
    notifyListeners();
  }

  CaptureSettings toCaptureSettings() => CaptureSettings(
        showWeather: showWeather,
        showAccuracy: showAccuracy,
        showAddress: showAddress,
        showCoordinates: showCoordinates,
        opacity: opacity,
        showBorder: showBorder,
        layout: layout,
        showMiniMap: showMiniMap,
        mapZoomLevel: mapZoomLevel,
        dateFormat: dateFormat,
        timeFormat: timeFormat,
        fontSize: fontSize,
        appName: appName,
        customLogoBytes: customLogoBytes,
      );

  double get previewFontScale =>
      fontSize == 'small' ? 0.8 : fontSize == 'large' ? 1.2 : 1.0;
}
