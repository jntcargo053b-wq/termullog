// lib/services/pod_location_service.dart
// ============================================================
// POD LOCATION SERVICE
// ============================================================
// - startup: lastKnownPosition (OS cache via getLastKnownPosition)
//            + SharedPreferences (koordinat + alamat sesi sebelumnya)
// - geocode: prefetch saat startup dari last known (paralel)
//            update hanya jika posisi bergerak > _geocodeMoveTreshold
// - distanceFilter: 0 saat acquiring, 5 setelah locked
// - weather: fetch paralel dari last known saat startup
// ============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pod_gps_engine.dart';
import 'pod_address_resolver.dart';
import 'weather_service.dart';

export 'pod_gps_engine.dart' show PodConfidence, PodConfidenceLabel, PodLockResult;

// ── State ────────────────────────────────────────────────────
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
  final bool isFastAddress;
  final bool isFallbackLock;

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
    this.isFallbackLock = false,
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
    bool? isFallbackLock,
  }) => PodLocationState(
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
    isFallbackLock: isFallbackLock ?? this.isFallbackLock,
  );
}

// ═══════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════
class PodLocationService {
  // Singleton
  static final PodLocationService _instance = PodLocationService._internal();
  static PodLocationService get instance => _instance;
  PodLocationService._internal();

  // Dependencies
  final PodGpsEngine   _gpsEngine      = PodGpsEngine();
  final WeatherService _weatherService = WeatherService();

  StreamSubscription<Position>? _positionStream;
  Timer? _weatherTimer;

  // State
  final _stateController = BehaviorSubject<PodLocationState>.seeded(
    const PodLocationState(),
  );
  Stream<PodLocationState> get stream => _stateController.stream;
  PodLocationState get currentState    => _stateController.value;

  // Config
  static const Duration _weatherInterval    = Duration(minutes: 15);
  static const String   _prefLat            = 'last_known_lat';
  static const String   _prefLon            = 'last_known_lon';
  static const String   _prefAddress        = 'last_known_address';
  static const int      _gridRes            = 10000; // ~10m grid
  // Geocode ulang hanya jika posisi bergerak lebih dari ini dari last geocode
  static const double   _geocodeMoveTreshold = 50.0; // meter

  // Cache geocode (grid-key → address)
  final Map<String, String> _geocodeCache = {};
  static const int _maxCache = 200;

  // Flags
  bool _running         = false;
  bool _geocodeDone     = false;    // satu kali geocode per session
  bool _locked          = false;    // sudah switch ke distanceFilter 5
  DateTime? _lastWeather;

  // Posisi terakhir saat geocode dilakukan — untuk deteksi pergerakan
  double? _lastGeocodeLat;
  double? _lastGeocodeLon;

  // ── Public ──────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    _running = true;

    try {
      await _loadLastKnown();

      if (!await _checkPermission()) {
        _emit(currentState.copyWith(
          confidence: PodConfidence.poor,
          address: 'Izin lokasi ditolak',
        ));
        _running = false;
        return;
      }

      await _startStream(locked: false); // mulai dengan distanceFilter 0
      _startWeatherTimer();

      // Fetch weather paralel dari last known tanpa tunggu GPS lock
      final s = currentState;
      if (s.lat != null && s.lon != null) {
        unawaited(_updateWeather(s.lat!, s.lon!));
      }

      if (kDebugMode) debugPrint('PodLocationService: started');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: start error $e');
      _running = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _positionStream?.cancel();
    _positionStream = null;
    _weatherTimer?.cancel();
    _weatherTimer = null;
    _gpsEngine.dispose();
    if (kDebugMode) debugPrint('PodLocationService: stopped');
  }

  Future<void> restart() async {
    await stop();
    _gpsEngine.reset();
    _geocodeDone    = false;
    _locked         = false;
    _lastGeocodeLat = null;
    _lastGeocodeLon = null;
    await start();
  }

  Future<void> refreshWeather() async {
    final s = currentState;
    if (s.lat != null && s.lon != null) await _updateWeather(s.lat!, s.lon!);
  }

  void dispose() {
    _weatherTimer?.cancel();
    _positionStream?.cancel();
    _stateController.close();
    PodAddressResolver.close();
    _gpsEngine.dispose();
  }

  // ── Stream ───────────────────────────────────────────────────

  Future<void> _startStream({required bool locked}) async {
    await _positionStream?.cancel();

    // Inject OS cached position sebelum stream dimulai (hanya saat acquiring)
    if (!locked) {
      try {
        final osLast = await Geolocator.getLastKnownPosition();
        if (osLast != null && !osLast.isMocked) {
          _gpsEngine.processSample(osLast);
          final conf     = _gpsEngine.confidence;
          final lock     = _gpsEngine.lockResult;
          final progress = _gpsEngine.lockProgress;
          _emit(currentState.copyWith(
            lat:          osLast.latitude,
            lon:          osLast.longitude,
            accuracy:     osLast.accuracy,
            confidence:   conf,
            lockResult:   lock,
            lockProgress: progress,
            isFallbackLock: _gpsEngine.isFallbackLock,
          ));
          if (kDebugMode) {
            debugPrint('PodLocationService: OS lastKnown injected '
                'acc=${osLast.accuracy.toStringAsFixed(1)}m conf=$conf');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PodLocationService: getLastKnownPosition error $e');
      }
    }

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: locked
          ? PodGpsEngine.distanceFilterLocked.toInt()
          : PodGpsEngine.distanceFilterAcquiring.toInt(),
      forceLocationManager: false, // pakai fused provider
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _onPosition,
      onError: (e) => debugPrint('PodLocationService: stream error $e'),
    );

    if (kDebugMode) {
      debugPrint('PodLocationService: stream started distanceFilter=${locked ? 5 : 0}m');
    }
  }

  // ── Position handler ─────────────────────────────────────────

  void _onPosition(Position raw) async {
    if (!_running) return;

    if (raw.isMocked) {
      _gpsEngine.reset();
      _emit(currentState.copyWith(
        confidence: PodConfidence.poor,
        address: 'GPS Mock terdeteksi',
      ));
      return;
    }

    final upgraded = _gpsEngine.processSample(raw);
    final conf     = _gpsEngine.confidence;
    final lock     = _gpsEngine.lockResult;
    final progress = _gpsEngine.lockProgress;

    final lat = lock?.centroidLat ?? raw.latitude;
    final lon = lock?.centroidLon ?? raw.longitude;
    final acc = lock?.accuracy    ?? raw.accuracy;

    _emit(currentState.copyWith(
      lat:            lat,
      lon:            lon,
      accuracy:       acc,
      confidence:     conf,
      lockResult:     lock,
      lockProgress:   progress,
      isFallbackLock: _gpsEngine.isFallbackLock,
    ));

    // Switch distanceFilter ke 5m setelah locked
    if (!_locked && _gpsEngine.isLocked) {
      _locked = true;
      await _startStream(locked: true);
    }

    // Geocode: saat pertama canCapture ATAU jika posisi bergerak > _geocodeMoveTreshold
    final shouldReocode = _geocodeDone &&
        _lastGeocodeLat != null &&
        _lastGeocodeLon != null &&
        PodGpsEngine.haversinePublic(_lastGeocodeLat!, _lastGeocodeLon!, lat, lon) > _geocodeMoveTreshold;

    if ((!_geocodeDone && conf.canCapture) || shouldReocode) {
      _geocodeDone = true;
      _lastGeocodeLat = lat;
      _lastGeocodeLon = lon;
      await _geocode(lat, lon);
    }

    // Weather: saat upgrade confidence atau sudah waktunya
    if (upgraded || _weatherDue()) {
      await _updateWeather(lat, lon);
    }
  }

  // ── Geocode ──────────────────────────────────────────────────

  Future<void> _geocode(double lat, double lon) async {
    final key = _gridKey(lat, lon);

    // Cache hit
    if (_geocodeCache.containsKey(key)) {
      _emit(currentState.copyWith(
        address:      _geocodeCache[key]!,
        fromCache:    true,
        addressLoading: false,
      ));
      return;
    }

    _emit(currentState.copyWith(addressLoading: true));

    try {
      final address = await PodAddressResolver.resolve(lat, lon);

      if (address.isNotEmpty && !address.contains('GPS:')) {
        _geocodeCache[key] = address;
        if (_geocodeCache.length > _maxCache) {
          final remove = _geocodeCache.keys.take(50).toList();
          for (final k in remove) _geocodeCache.remove(k);
        }
        await _saveLastKnown(lat, lon, address);
      }

      _emit(currentState.copyWith(
        address:        address,
        fromCache:      false,
        addressLoading: false,
        isFastAddress:  false,
      ));

      if (kDebugMode) debugPrint('PodLocationService: geocode done → $address');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: geocode error $e');
      _emit(currentState.copyWith(addressLoading: false));
    }
  }

  // ── Weather ──────────────────────────────────────────────────

  bool _weatherDue() {
    if (_lastWeather == null) return true;
    return DateTime.now().difference(_lastWeather!) > _weatherInterval;
  }

  void _startWeatherTimer() {
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(_weatherInterval, (_) async {
      final s = currentState;
      if (s.lat != null && s.lon != null) await _updateWeather(s.lat!, s.lon!);
    });
  }

  Future<void> _updateWeather(double lat, double lon) async {
    try {
      final w = await _weatherService.fetchWeather(lat, lon);
      _emit(currentState.copyWith(weather: w));
      _lastWeather = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: weather error $e');
    }
  }

  // ── Last known ───────────────────────────────────────────────

  Future<void> _loadLastKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat     = prefs.getDouble(_prefLat);
      final lon     = prefs.getDouble(_prefLon);
      final address = prefs.getString(_prefAddress);

      if (lat != null && lon != null && address != null && address.isNotEmpty) {
        _emit(currentState.copyWith(
          lat:          lat,
          lon:          lon,
          address:      address,
          fromCache:    true,
          isFastAddress: true,
        ));

        // Prefill geocode cache supaya tidak re-query Nominatim untuk posisi yang sama
        final key = _gridKey(lat, lon);
        _geocodeCache[key] = address;
        // Anggap geocode sudah done; akan di-update hanya jika posisi bergerak > 50m
        _geocodeDone       = true;
        _lastGeocodeLat    = lat;
        _lastGeocodeLon    = lon;

        if (kDebugMode) debugPrint('PodLocationService: loaded last known → $address');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: load last known error $e');
    }
  }

  Future<void> _saveLastKnown(double lat, double lon, String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setDouble(_prefLat, lat),
        prefs.setDouble(_prefLon, lon),
        prefs.setString(_prefAddress, address),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: save last known error $e');
    }
  }

  // ── Permission ───────────────────────────────────────────────

  Future<bool> _checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm != LocationPermission.denied &&
           perm != LocationPermission.deniedForever;
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _gridKey(double lat, double lon) {
    final gLat = (lat * _gridRes).round();
    final gLon = (lon * _gridRes).round();
    return '$gLat,$gLon';
  }

  void _emit(PodLocationState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
