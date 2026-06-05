// lib/services/pod_location_service.dart
// ============================================================
// POD LOCATION SERVICE
// ============================================================
// Layanan terpusat yang mengkoordinasikan:
//   - PodGpsEngine (akuisisi & stabilisasi koordinat)
//   - PodAddressResolver (geocoding multi-provider)
//   - Weather API (open-meteo)
//   - Cross-session cache (SharedPreferences)
//
// Didesain sebagai singleton yang di-inject ke CameraScreen.
// Expose Stream<PodLocationState> agar UI dapat react.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'pod_gps_engine.dart';
import 'pod_address_resolver.dart';

// ── State snapshot yang dikirim ke UI ─────────────────────
class PodLocationState {
  /// Koordinat resmi untuk watermark (centroid dari engine)
  final double? lat;
  final double? lon;
  final double? accuracy;

  /// Confidence level
  final PodConfidence confidence;

  /// Alamat hasil geocode
  final String address;

  /// Cuaca
  final String weather;

  /// True jika sedang fetching alamat
  final bool addressLoading;

  /// True jika data berasal dari cache sesi sebelumnya
  final bool fromCache;

  /// Lock result lengkap (untuk audit/watermark)
  final PodLockResult? lockResult;

  /// Progress 0–1 menuju lock
  final double lockProgress;

  const PodLocationState({
    this.lat,
    this.lon,
    this.accuracy,
    this.confidence = PodConfidence.searching,
    this.address = '',
    this.weather = '',
    this.addressLoading = false,
    this.fromCache = false,
    this.lockResult = null,
    this.lockProgress = 0.0,
  });

  PodLocationState copyWith({
    double? lat,
    double? lon,
    double? accuracy,
    PodConfidence? confidence,
    String? address,
    String? weather,
    bool? addressLoading,
    bool? fromCache,
    PodLockResult? lockResult,
    double? lockProgress,
  }) {
    return PodLocationState(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracy: accuracy ?? this.accuracy,
      confidence: confidence ?? this.confidence,
      address: address ?? this.address,
      weather: weather ?? this.weather,
      addressLoading: addressLoading ?? this.addressLoading,
      fromCache: fromCache ?? this.fromCache,
      lockResult: lockResult ?? this.lockResult,
      lockProgress: lockProgress ?? this.lockProgress,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PodLocationService
// ═══════════════════════════════════════════════════════════
class PodLocationService {
  PodLocationService._();
  static final PodLocationService instance = PodLocationService._();

  final PodGpsEngine _engine = PodGpsEngine();

  // Stream controller
  final _controller = StreamController<PodLocationState>.broadcast();
  Stream<PodLocationState> get stream => _controller.stream;

  PodLocationState _state = const PodLocationState();
  PodLocationState get currentState => _state;

  StreamSubscription<Position>? _posSub;
  bool _started = false;
  bool _disposed = false;

  // Address throttle
  double? _lastGeocodedLat;
  double? _lastGeocodedLon;
  double? _lastGeocodedAcc;
  bool _addressPending = false;
  static const double _geocodeMinMove = 8.0;  // meter
  static const double _geocodeMinAccImprove = 4.0;

  // Weather throttle
  DateTime? _lastWeatherFetch;
  static const Duration _weatherInterval = Duration(minutes: 30);

  // Persistent session cache
  static const String _sessionKey = 'pod_session_cache_v1';
  static const Duration _sessionMaxAge = Duration(hours: 12);

  // ── Lifecycle ─────────────────────────────────────────────

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    // Muat persistent cache & address cache paralel
    await Future.wait([
      _loadSessionCache(),
      PodAddressResolver.loadPersistentCache(),
    ]);

    await _requestPermission();
    _tryOsLastKnown();
    _startStream();
  }

  Future<void> restart() async {
    await _posSub?.cancel();
    _posSub = null;
    _started = false;
    _engine.reset();
    PodAddressResolver.reopen();
    _lastGeocodedLat = null;
    _lastGeocodedLon = null;
    _lastGeocodedAcc = null;
    _lastWeatherFetch = null;
    await start();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _posSub?.cancel();
    PodAddressResolver.close();
    _controller.close();
  }

  // ── GPS Stream ────────────────────────────────────────────

  Future<void> _requestPermission() async {
    try { await Geolocator.requestPermission(); } catch (_) {}
  }

  Future<void> _tryOsLastKnown() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return;
      if (last.accuracy > 30.0) return;
      final age = last.timestamp != null
          ? DateTime.now().difference(last.timestamp!)
          : Duration.zero;
      if (age > const Duration(minutes: 2)) return;

      // Pakai sebagai seed awal engine
      _engine.processSample(last);
      _updateStateFromEngine(last);
    } catch (_) {}
  }

  void _startStream() {
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2, // meter — lebih sensitif dari sebelumnya
        ),
      ).listen(_onPosition, onError: (_) {});
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: stream error → $e');
    }
  }

  void _onPosition(Position pos) {
    if (_disposed) return;

    // Mock GPS check
    if (pos.isMocked) {
      _emit(_state.copyWith(
        confidence: PodConfidence.poor,
        address: '⚠️ Mock GPS terdeteksi',
      ));
      return;
    }

    final upgraded = _engine.processSample(pos);
    _updateStateFromEngine(pos);

    final lockResult = _engine.lockResult;
    if (lockResult == null) return;

    // Tentukan koordinat untuk geocode
    final geocodeLat = lockResult.centroidLat;
    final geocodeLon = lockResult.centroidLon;
    final geocodeAcc = lockResult.accuracy;

    // Geocode jika:
    //   a) baru dapat lock (upgraded ke good/excellent)
    //   b) bergerak >8m dari geocode terakhir
    //   c) akurasi membaik ≥4m dari geocode terakhir
    final shouldGeocode = _engine.canCapture &&
        (upgraded ||
            _needsGeocode(geocodeLat, geocodeLon, geocodeAcc));

    if (shouldGeocode) {
      _resolveAddress(geocodeLat, geocodeLon, geocodeAcc);
    }

    // Weather setiap 30 menit
    if (_engine.canCapture) {
      _maybeLoadWeather(geocodeLat, geocodeLon);
    }
  }

  void _updateStateFromEngine(Position raw) {
    final lockResult = _engine.lockResult;
    double? lat, lon, acc;

    if (lockResult != null) {
      lat = lockResult.centroidLat;
      lon = lockResult.centroidLon;
      acc = lockResult.accuracy;
    } else {
      lat = raw.latitude;
      lon = raw.longitude;
      acc = raw.accuracy;
    }

    _emit(_state.copyWith(
      lat: lat,
      lon: lon,
      accuracy: acc,
      confidence: _engine.confidence,
      lockResult: lockResult,
      lockProgress: _engine.lockProgress,
      fromCache: false,
    ));
  }

  // ── Address resolver ──────────────────────────────────────

  bool _needsGeocode(double lat, double lon, double acc) {
    if (_lastGeocodedLat == null) return true;
    final d = Geolocator.distanceBetween(
        _lastGeocodedLat!, _lastGeocodedLon!, lat, lon);
    if (d >= _geocodeMinMove) return true;
    if (_lastGeocodedAcc != null &&
        (_lastGeocodedAcc! - acc) >= _geocodeMinAccImprove) return true;
    return false;
  }

  void _resolveAddress(double lat, double lon, double acc) {
    if (_addressPending) return;
    _addressPending = true;
    _emit(_state.copyWith(addressLoading: true));

    PodAddressResolver.resolve(lat, lon).then((address) {
      if (_disposed) return;
      _addressPending = false;
      _lastGeocodedLat = lat;
      _lastGeocodedLon = lon;
      _lastGeocodedAcc = acc;

      _emit(_state.copyWith(
        address: address,
        addressLoading: false,
        fromCache: false,
      ));

      // Simpan ke session cache
      _saveSessionCache(lat, lon, acc, address, _state.weather);
    }).catchError((_) {
      _addressPending = false;
      _emit(_state.copyWith(addressLoading: false));
    });
  }

  // ── Weather ───────────────────────────────────────────────

  void _maybeLoadWeather(double lat, double lon) {
    if (_lastWeatherFetch != null &&
        DateTime.now().difference(_lastWeatherFetch!) < _weatherInterval) return;
    _lastWeatherFetch = DateTime.now();

    _fetchWeather(lat, lon).then((w) {
      if (_disposed || w.isEmpty) return;
      _emit(_state.copyWith(weather: w));
      if (_state.lat != null) {
        _saveSessionCache(
            _state.lat!, _state.lon!, _state.accuracy ?? 99, _state.address, w);
      }
    }).catchError((_) {});
  }

  static http.Client? _weatherClient;

  static Future<String> _fetchWeather(double lat, double lon) async {
    _weatherClient ??= http.Client();
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(5)}'
        '&longitude=${lon.toStringAsFixed(5)}'
        '&current=temperature_2m,weather_code&timezone=auto',
      );
      final res = await _weatherClient!.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      if (current == null) return '';
      final temp = (current['temperature_2m'] as num?)?.toStringAsFixed(0) ?? '--';
      final code = (current['weather_code'] as num?)?.toInt() ?? 0;
      return '${_wmo(code)} $temp°C';
    } catch (_) {
      return '';
    }
  }

  static String _wmo(int c) {
    if (c == 0)  return '☀️ Cerah';
    if (c <= 3)  return '⛅ Berawan';
    if (c <= 49) return '🌫️ Berkabut';
    if (c <= 57) return '🌦️ Gerimis';
    if (c <= 67) return '🌧️ Hujan';
    if (c <= 77) return '❄️ Salju';
    if (c <= 82) return '🌧️ Hujan Lebat';
    if (c <= 99) return '⚡ Badai Petir';
    return '🌡️';
  }

  // ── Session cache (cross-session) ─────────────────────────

  Future<void> _loadSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(map['savedAt'] as String? ?? '');
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > _sessionMaxAge) return;
      final lat = (map['lat'] as num?)?.toDouble();
      final lon = (map['lon'] as num?)?.toDouble();
      final acc = (map['acc'] as num?)?.toDouble();
      final address = map['address'] as String? ?? '';
      final weather = map['weather'] as String? ?? '';
      if (lat == null || lon == null || address.isEmpty) return;

      _state = PodLocationState(
        lat: lat,
        lon: lon,
        accuracy: acc,
        confidence: PodConfidence.fair,
        address: address,
        weather: weather,
        fromCache: true,
        lockProgress: 0.0,
      );
      _emit(_state);
      if (kDebugMode) debugPrint('PodLocationService: session cache loaded → $address');
    } catch (_) {}
  }

  Future<void> _saveSessionCache(
      double lat, double lon, double acc, String address, String weather) async {
    if (address.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'lat': lat,
        'lon': lon,
        'acc': acc,
        'address': address,
        'weather': weather,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_sessionKey, jsonEncode(map));
    } catch (_) {}
  }

  // ── Emit helper ───────────────────────────────────────────
  void _emit(PodLocationState state) {
    _state = state;
    if (!_controller.isClosed) _controller.add(state);
  }
}
