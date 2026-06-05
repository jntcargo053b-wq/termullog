// lib/services/pod_location_service.dart
// ============================================================
// POD LOCATION SERVICE — Proof of Delivery Edition
// ============================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';

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
  static const Duration _geocodeDebounceDuration = Duration(milliseconds: 800);
  static const double _minAccuracyForGeocode = 20.0;  // meter
  static const int _gridResolution = 10000;  // 10m precision untuk grid cache
  
  // Grid cache untuk reverse geocode (10m x 10m)
  final Map<String, String> _geocodeGridCache = {};
  static const int _maxGridCacheSize = 200;
  
  // Tracking untuk conditional geocode
  String? _lastGeocodeGridKey;
  DateTime? _lastGeocodeTime;
  static const Duration _minGeocodeInterval = Duration(seconds: 5);
  
  // GPS settings
  bool _isRunning = false;
  
  // ── Public Methods ─────────────────────────────────────────

  /// Start GPS listening (dipanggil dari CameraScreen)
  Future<void> start() async {
    if (_isRunning) {
      if (kDebugMode) debugPrint('PodLocationService: Already running');
      return;
    }
    
    _isRunning = true;
    
    try {
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
      
      if (kDebugMode) debugPrint('PodLocationService: Started successfully');
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

  /// Restart GPS (dipanggil saat app resume)
  Future<void> restart() async {
    if (kDebugMode) debugPrint('PodLocationService: Restarting...');
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
      distanceFilter: 2,  // Update setiap 2 meter
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

    // 🔴 KRITIS: Anti-spoof hard reset
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
    
    // Update state
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

    // 🔴 OPTIMASI: Conditional geocode — hanya saat confidence good/excellent
    // DAN accuracy cukup baik
    if ((engineConfidence == PodConfidence.good || 
         engineConfidence == PodConfidence.excellent) &&
        accuracy <= _minAccuracyForGeocode) {
      _debouncedGeocode(centroid.lat, centroid.lon);
    } else if (kDebugMode) {
      debugPrint('PodLocationService: Skip geocode - '
          'confidence=${engineConfidence.label}, acc=${accuracy.toStringAsFixed(1)}m');
    }

    // Update weather jika confidence meningkat atau setiap interval
    if (upgraded || _shouldUpdateWeather()) {
      await _updateWeather(centroid.lat, centroid.lon);
    }
  }

  // ── Geocode dengan Grid Cache & Conditional ────────────────

  String _gridKey(double lat, double lon) {
    final gridLat = (lat * _gridResolution).round();
    final gridLon = (lon * _gridResolution).round();
    return '$gridLat,$gridLon';
  }

  void _debouncedGeocode(double lat, double lon) {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(_geocodeDebounceDuration, () async {
      await _resolveAddressWithCache(lat, lon);
    });
  }

  Future<void> _resolveAddressWithCache(double lat, double lon) async {
    final gridKey = _gridKey(lat, lon);
    final now = DateTime.now();
    
    // Check rate limiting
    if (_lastGeocodeTime != null &&
        now.difference(_lastGeocodeTime!) < _minGeocodeInterval &&
        _lastGeocodeGridKey == gridKey) {
      if (kDebugMode) debugPrint('PodLocationService: Geocode rate limited (same grid)');
      return;
    }
    
    // Grid cache hit
    if (_geocodeGridCache.containsKey(gridKey)) {
      if (kDebugMode) debugPrint('PodLocationService: Grid cache HIT for $gridKey');
      _stateController.add(
        currentState.copyWith(
          address: _geocodeGridCache[gridKey]!,
          fromCache: true,
          addressLoading: false,
        ),
      );
      _lastGeocodeTime = now;
      _lastGeocodeGridKey = gridKey;
      return;
    }
    
    // Fetch from resolver
    if (kDebugMode) debugPrint('PodLocationService: Geocode fetching...');
    _stateController.add(currentState.copyWith(addressLoading: true));
    
    try {
      final address = await PodAddressResolver.resolve(lat, lon);
      
      // Store in grid cache
      if (address.isNotEmpty && !address.contains('GPS:')) {
        _geocodeGridCache[gridKey] = address;
        _lastGeocodeGridKey = gridKey;
        _lastGeocodeTime = now;
        
        // Limit cache size
        if (_geocodeGridCache.length > _maxGridCacheSize) {
          final keysToRemove = _geocodeGridCache.keys.take(50).toList();
          for (var key in keysToRemove) {
            _geocodeGridCache.remove(key);
          }
          if (kDebugMode) debugPrint('PodLocationService: Trimmed grid cache to ${_geocodeGridCache.length}');
        }
      }
      
      _stateController.add(
        currentState.copyWith(
          address: address,
          fromCache: false,
          addressLoading: false,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: Geocode error - $e');
      _stateController.add(currentState.copyWith(addressLoading: false));
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
      // Keep existing weather on error
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
