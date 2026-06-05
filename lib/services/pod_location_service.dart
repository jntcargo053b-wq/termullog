// lib/services/pod_location_service.dart
// ============================================================
// POD LOCATION SERVICE — Two-Phase Geocode Edition
// ============================================================
// Fase 1 (1-3 detik): accuracy ≤ 50m → alamat cepat (kecamatan/kota)
// Fase 2 (5-8 detik): accuracy ≤ 15m + confidence good → alamat akurat (jalan + RT/RW)
//
// Fitur:
//   - GPS start dari main() agar alamat siap saat kamera dibuka
//   - Last known position dari SharedPreferences (langsung tampil)
//   - Grid cache (10m) untuk efisiensi
//   - Rate limiting dan debounce
//   - Reset two‑phase flags saat restart
// ============================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pod_gps_engine.dart';
import 'pod_address_resolver.dart';
import 'weather_service.dart';
import 'settings_cache.dart';

// Re-export PodConfidence dari pod_gps_engine
export 'pod_gps_engine.dart' show PodConfidence, PodConfidenceLabel, PodLockResult;

// ═══════════════════════════════════════════════════════════════
// STATE OBJECT
// ═══════════════════════════════════════════════════════════════

/// State lengkap lokasi untuk UI
class PodLocationState {
  final double? lat;
  final double? lon;
  final double? accuracy;
  final PodConfidence confidence;
  final PodLockResult? lockResult;
  final String address;
  final String weather;
  final bool addressLoading;
  final bool fromCache;
  final double lockProgress;
  final bool isFastAddress; // true = alamat cepat (fase 1), false = alamat akurat

  const PodLocationState({
    this.lat,
    this.lon,
    this.accuracy,
    this.confidence = PodConfidence.searching,
    this.lockResult,
    this.address = '',
    this.weather = '',
    this.addressLoading = false,
    this.fromCache = false,
    this.lockProgress = 0.0,
    this.isFastAddress = false,
  });

  PodLocationState copyWith({
    double? lat,
    double? lon,
    double? accuracy,
    PodConfidence? confidence,
    PodLockResult? lockResult,
    String? address,
    String? weather,
    bool? addressLoading,
    bool? fromCache,
    double? lockProgress,
    bool? isFastAddress,
  }) {
    return PodLocationState(
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracy: accuracy ?? this.accuracy,
      confidence: confidence ?? this.confidence,
      lockResult: lockResult ?? this.lockResult,
      address: address ?? this.address,
      weather: weather ?? this.weather,
      addressLoading: addressLoading ?? this.addressLoading,
      fromCache: fromCache ?? this.fromCache,
      lockProgress: lockProgress ?? this.lockProgress,
      isFastAddress: isFastAddress ?? this.isFastAddress,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MAIN SERVICE
// ═══════════════════════════════════════════════════════════════

class PodLocationService {
  // ── Singleton ──────────────────────────────────────────────
  static final PodLocationService _instance = PodLocationService._internal();
  static PodLocationService get instance => _instance;
  PodLocationService._internal();

  // ── Dependencies ───────────────────────────────────────────
  final PodGpsEngine _gpsEngine = PodGpsEngine();
  final WeatherService _weatherService = WeatherService();
  StreamSubscription<Position>? _positionStream;
  Timer? _weatherTimer;
  Timer? _geocodeDebounce;

  // ── State Management ───────────────────────────────────────
  final _stateController = BehaviorSubject<PodLocationState>.seeded(
    const PodLocationState(),
  );
  Stream<PodLocationState> get stream => _stateController.stream;
  PodLocationState get currentState => _stateController.value;

  // ── Configuration ──────────────────────────────────────────
  static const Duration _weatherUpdateInterval = Duration(minutes: 15);
  static const Duration _geocodeDebounceDuration = Duration(milliseconds: 300);
  
  // Two‑phase thresholds
  static const double _fastGeocodeAccuracy = 50.0;    // Phase 1
  static const double _accurateGeocodeAccuracy = 15.0; // Phase 2
  
  static const int _gridResolution = 10000; // 10 meter precision
  
  // Caches
  final Map<String, String> _fastAddressCache = {};
  final Map<String, String> _accurateAddressCache = {};
  static const int _maxCacheSize = 200;
  
  // Two‑phase tracking
  bool _hasFastGeocode = false;
  bool _hasAccurateGeocode = false;
  
  // Last known position (persistent)
  static const String _prefLastLat = 'last_known_lat';
  static const String _prefLastLon = 'last_known_lon';
  static const String _prefLastAddress = 'last_known_address';
  
  // GPS running flag
  bool _isRunning = false;
  
  // ── Public Methods ─────────────────────────────────────────

  /// Start GPS listening (dipanggil dari main())
  Future<void> start() async {
    if (_isRunning) {
      if (kDebugMode) debugPrint('PodLocationService: Already running');
      return;
    }
    
    _isRunning = true;
    
    try {
      // Load last known position dari SharedPreferences
      await _loadLastKnownPosition();
      
      // Request permission
      final permission = await _checkPermissions();
      if (!permission) {
        _stateController.add(
          currentState.copyWith(
            confidence: PodConfidence.poor,
            address: 'Izin lokasi ditolak',
          ),
        );
        _isRunning = false;
        return;
      }

      // Start position stream
      await _initLocationStream();
      
      // Start weather timer
      _startWeatherTimer();
      
      if (kDebugMode) debugPrint('PodLocationService: Started successfully (Two-Phase)');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Start error - $e');
      _isRunning = false;
      rethrow;
    }
  }

  /// Stop GPS listening
  Future<void> stop() async {
    if (!_isRunning) return;
    
    _isRunning = false;
    await _positionStream?.cancel();
    _positionStream = null;
    _weatherTimer?.cancel();
    _geocodeDebounce?.cancel();
    
    if (kDebugMode) debugPrint('PodLocationService: Stopped');
  }

  /// Restart GPS (dipanggil saat app resume) – reset two‑phase flags
  Future<void> restart() async {
    if (kDebugMode) debugPrint('PodLocationService: Restarting...');
    
    // 🔴 Reset two‑phase flags agar geocode bisa dimulai ulang
    _hasFastGeocode = false;
    _hasAccurateGeocode = false;
    
    await stop();
    _gpsEngine.reset();
    await start();
  }

  /// Force refresh weather now
  Future<void> refreshWeather() async {
    final state = currentState;
    if (state.lat != null && state.lon != null) {
      await _updateWeather(state.lat!, state.lon!);
    }
  }

  // ── Private Methods ────────────────────────────────────────

  Future<bool> _checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (kDebugMode) debugPrint('PodLocationService: Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (kDebugMode) debugPrint('PodLocationService: Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (kDebugMode) debugPrint('PodLocationService: Location permission permanently denied');
      return false;
    }

    return true;
  }

  Future<void> _initLocationStream() async {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onPositionUpdate,
      onError: (error) {
        if (kDebugMode) debugPrint('PodLocationService: Position stream error - $error');
      },
    );
  }

  void _onPositionUpdate(Position rawPos) async {
    if (!_isRunning) return;

    // Anti-spoof hard reset
    if (rawPos.isMocked) {
      if (kDebugMode) debugPrint('PodLocationService: MOCK GPS detected — HARD RESET');
      _gpsEngine.reset();
      _stateController.add(
        currentState.copyWith(
          confidence: PodConfidence.poor,
          address: 'GPS Mock terdeteksi',
        ),
      );
      return;
    }

    // Process sample melalui GPS engine
    final upgraded = _gpsEngine.processSample(rawPos);
    
    // Update state dengan data terbaru dari engine
    final engineConfidence = _gpsEngine.confidence;
    final lockResult = _gpsEngine.lockResult;
    final progress = _gpsEngine.lockProgress;
    
    final centroid = lockResult != null
        ? (lat: lockResult.centroidLat, lon: lockResult.centroidLon)
        : (lat: rawPos.latitude, lon: rawPos.longitude);
    
    final accuracy = lockResult?.accuracy ?? rawPos.accuracy;
    
    // Update state (koordinat, akurasi, confidence)
    _stateController.add(
      currentState.copyWith(
        lat: centroid.lat,
        lon: centroid.lon,
        accuracy: accuracy,
        confidence: engineConfidence,
        lockResult: lockResult,
        lockProgress: progress,
      ),
    );

    // 🔴 PHASE 1: FAST GEOCODE (accuracy ≤ 50m)
    if (!_hasFastGeocode && accuracy <= _fastGeocodeAccuracy) {
      _hasFastGeocode = true;
      if (kDebugMode) debugPrint('PodLocationService: 🔴 PHASE 1 - Fast geocode (accuracy=${accuracy.toStringAsFixed(0)}m)');
      await _resolveAddressWithCache(centroid.lat, centroid.lon, isFastGeocode: true);
    }
    
    // 🔴 PHASE 2: ACCURATE GEOCODE (accuracy ≤ 15m + confidence good/excellent)
    if (!_hasAccurateGeocode && 
        accuracy <= _accurateGeocodeAccuracy && 
        (engineConfidence == PodConfidence.good || engineConfidence == PodConfidence.excellent)) {
      _hasAccurateGeocode = true;
      if (kDebugMode) debugPrint('PodLocationService: 🔴 PHASE 2 - Accurate geocode (accuracy=${accuracy.toStringAsFixed(0)}m, confidence=${engineConfidence.label})');
      await _resolveAddressWithCache(centroid.lat, centroid.lon, isFastGeocode: false);
    }

    // Update weather jika confidence meningkat
    if (upgraded || _shouldUpdateWeather()) {
      await _updateWeather(centroid.lat, centroid.lon);
    }
  }

  String _gridKey(double lat, double lon) {
    final gridLat = (lat * _gridResolution).round();
    final gridLon = (lon * _gridResolution).round();
    return '$gridLat,$gridLon';
  }

  void _debouncedGeocode(double lat, double lon, {bool isFastGeocode = false}) {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(_geocodeDebounceDuration, () async {
      await _resolveAddressWithCache(lat, lon, isFastGeocode: isFastGeocode);
    });
  }

  Future<void> _resolveAddressWithCache(double lat, double lon, {required bool isFastGeocode}) async {
    final gridKey = _gridKey(lat, lon);
    final cache = isFastGeocode ? _fastAddressCache : _accurateAddressCache;
    
    // Cache hit
    if (cache.containsKey(gridKey)) {
      if (kDebugMode) debugPrint('PodLocationService: ${isFastGeocode ? "FAST" : "ACCURATE"} cache HIT for $gridKey');
      final cachedAddress = cache[gridKey]!;
      _stateController.add(
        currentState.copyWith(
          address: cachedAddress,
          fromCache: true,
          addressLoading: false,
          isFastAddress: isFastGeocode,
        ),
      );
      // Simpan ke last known jika ini alamat akurat
      if (!isFastGeocode && !cachedAddress.contains('GPS:')) {
        await _saveLastKnownPosition(lat, lon, cachedAddress);
      }
      return;
    }
    
    // Fetch dari resolver
    if (kDebugMode) debugPrint('PodLocationService: ${isFastGeocode ? "FAST" : "ACCURATE"} geocode fetching...');
    
    // Tampilkan loading hanya untuk accurate geocode
    if (!isFastGeocode) {
      _stateController.add(currentState.copyWith(addressLoading: true));
    }
    
    try {
      final address = await PodAddressResolver.resolve(lat, lon);
      
      if (address.isNotEmpty && !address.contains('GPS:')) {
        cache[gridKey] = address;
        
        // Limit cache size
        if (cache.length > _maxCacheSize) {
          final keysToRemove = cache.keys.take(50).toList();
          for (var key in keysToRemove) {
            cache.remove(key);
          }
          if (kDebugMode) debugPrint('PodLocationService: Trimmed ${isFastGeocode ? "FAST" : "ACCURATE"} cache');
        }
        
        // Simpan ke last known jika ini alamat akurat
        if (!isFastGeocode) {
          await _saveLastKnownPosition(lat, lon, address);
        }
      }
      
      _stateController.add(
        currentState.copyWith(
          address: address,
          fromCache: false,
          addressLoading: false,
          isFastAddress: isFastGeocode,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Geocode error - $e');
      if (!isFastGeocode) {
        _stateController.add(currentState.copyWith(addressLoading: false));
      }
    }
  }

  // ── Last Known Position (SharedPreferences) ─────────────────
  
  Future<void> _loadLastKnownPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastLat = prefs.getDouble(_prefLastLat);
      final lastLon = prefs.getDouble(_prefLastLon);
      final lastAddress = prefs.getString(_prefLastAddress);
      
      if (lastLat != null && lastLon != null && lastAddress != null && lastAddress.isNotEmpty) {
        if (kDebugMode) debugPrint('PodLocationService: Loaded last known: $lastAddress');
        _stateController.add(
          currentState.copyWith(
            lat: lastLat,
            lon: lastLon,
            address: lastAddress,
            fromCache: true,
            isFastAddress: true,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Load last known error - $e');
    }
  }

  Future<void> _saveLastKnownPosition(double lat, double lon, String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefLastLat, lat);
      await prefs.setDouble(_prefLastLon, lon);
      await prefs.setString(_prefLastAddress, address);
      if (kDebugMode) debugPrint('PodLocationService: Saved last known position');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Save last known error - $e');
    }
  }

  // ── Weather ────────────────────────────────────────────────

  DateTime? _lastWeatherUpdate;
  
  bool _shouldUpdateWeather() {
    if (_lastWeatherUpdate == null) return true;
    return DateTime.now().difference(_lastWeatherUpdate!) > _weatherUpdateInterval;
  }

  void _startWeatherTimer() {
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(_weatherUpdateInterval, (_) async {
      final state = currentState;
      if (state.lat != null && state.lon != null) {
        await _updateWeather(state.lat!, state.lon!);
      }
    });
  }

  Future<void> _updateWeather(double lat, double lon) async {
    try {
      final weather = await _weatherService.fetchWeather(lat, lon);
      _stateController.add(currentState.copyWith(weather: weather));
      _lastWeatherUpdate = DateTime.now();
      if (kDebugMode) debugPrint('PodLocationService: Weather updated - $weather');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Weather error - $e');
      // keep existing weather
    }
  }

  // ── Cleanup ────────────────────────────────────────────────

  void dispose() {
    _weatherTimer?.cancel();
    _positionStream?.cancel();
    _geocodeDebounce?.cancel();
    _stateController.close();
    PodAddressResolver.close();
    if (kDebugMode) debugPrint('PodLocationService: Disposed');
  }
}
