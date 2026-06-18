// lib/services/pod_location_service.dart
// ============================================================
// POD LOCATION SERVICE — On-Demand Mode
// ============================================================
// GPS TIDAK aktif terus-menerus. Engine hanya berjalan saat:
//   1. acquireForCapture() dipanggil (user buka kamera / tap capture)
//   2. Otomatis berhenti setelah lock ATAU timeout
//
// Lifecycle GPS:
//   idle      → tidak ada stream, baterai nol
//   acquiring → stream aktif, kumpul sample
//   locked    → stream berhenti, koordinat tersimpan
//   stale     → locked > _staleAfter, perlu re-acquire
//
// Cache:
//   - OS getLastKnownPosition()  → instant preview (<50ms)
//   - SharedPreferences          → koordinat + alamat sesi lalu
//   - Geocode: hanya fetch ulang jika bergerak >50m dari cache
//   - Weather: cache 15 menit, fetch paralel saat acquire
// ============================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pod_gps_engine.dart';
import 'pod_address_resolver.dart';
import 'weather_service.dart';
import '../models/resolved_location.dart';

export 'pod_gps_engine.dart' show PodConfidence, PodConfidenceLabel, PodLockResult;

// ── Status mode service ───────────────────────────────────────
enum PodGpsMode {
  idle,       // GPS off, tampilkan cache jika ada
  acquiring,  // Stream aktif, sedang mengumpul sample
  locked,     // Sudah lock, stream sudah berhenti
  stale,      // Lock lama > _staleAfter, perlu re-acquire
}

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
  final PodGpsMode mode;
  final ResolvedLocation? resolvedLocation;

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
    this.mode = PodGpsMode.idle,
    this.resolvedLocation,
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
    PodGpsMode? mode,
    ResolvedLocation? resolvedLocation,
  }) => PodLocationState(
    lat:            lat            ?? this.lat,
    lon:            lon            ?? this.lon,
    accuracy:       accuracy       ?? this.accuracy,
    confidence:     confidence     ?? this.confidence,
    lockResult:     lockResult     ?? this.lockResult,
    address:        address        ?? this.address,
    weather:        weather        ?? this.weather,
    addressLoading: addressLoading ?? this.addressLoading,
    fromCache:      fromCache      ?? this.fromCache,
    lockProgress:   lockProgress   ?? this.lockProgress,
    isFastAddress:  isFastAddress  ?? this.isFastAddress,
    isFallbackLock: isFallbackLock ?? this.isFallbackLock,
    mode:           mode           ?? this.mode,
    resolvedLocation: resolvedLocation ?? this.resolvedLocation,
  );

  bool get hasPosition => lat != null && lon != null;
  bool get canCapture  => confidence.canCapture;
  bool get isStale     => mode == PodGpsMode.stale;
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
  Timer? _staleTimer;
  Timer? _acquireTimeout;

  // ── Config ───────────────────────────────────────────────────
  static const Duration _staleAfter      = Duration(minutes: 10);
  // FIX: _acquireDeadline diselaraskan dengan engine _hardTimeout (10 s)
  // ditambah sedikit buffer (2 s) agar engine punya cukup waktu emit
  // fallback lock sebelum service memaksa stop stream.
  static const Duration _acquireDeadline = Duration(seconds: 12);
  static const String   _prefLat         = 'last_known_lat';
  static const String   _prefLon         = 'last_known_lon';
  static const String   _prefAddress     = 'last_known_address';
  static const int      _gridRes         = 10000;   // ~10m grid
  static const double   _geocodeMoveM    = 80.0;
  static const Duration _weatherMaxAge   = Duration(minutes: 15);

  // ── State ───────────────────────────────────────────────────
  final _stateCtrl = BehaviorSubject<PodLocationState>.seeded(
    const PodLocationState(),
  );
  Stream<PodLocationState> get stream => _stateCtrl.stream;
  PodLocationState get currentState    => _stateCtrl.value;

  final Map<String, String> _geocodeCache = {};
  static const int _maxCache = 200;

  bool      _initialized    = false;
  bool      _geocodeDone    = false;
  double?   _lastGeocodeLat;
  double?   _lastGeocodeLon;
  DateTime? _lastWeatherAt;
  DateTime? _lockedAt;

  // ── Init ────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadCachedState();
    if (kDebugMode) debugPrint('PodLocationService: init (idle, no GPS stream)');
  }

  // ── acquireForCapture ───────────────────────────────────────
  Future<void> acquireForCapture() async {
    final mode = currentState.mode;

    if (mode == PodGpsMode.locked) {
      if (kDebugMode) debugPrint('PodLocationService: already locked, skip acquire');
      return;
    }

    if (mode == PodGpsMode.acquiring) {
      if (kDebugMode) debugPrint('PodLocationService: already acquiring');
      return;
    }

    if (!await _checkPermission()) {
      _emit(currentState.copyWith(
        confidence: PodConfidence.poor,
        address: 'Izin lokasi ditolak',
        mode: PodGpsMode.idle,
      ));
      return;
    }

    await _startAcquire();
  }

  // ── releaseAfterCapture ─────────────────────────────────────
  void releaseAfterCapture() {
    _stopStream();
    if (currentState.mode == PodGpsMode.locked ||
        currentState.mode == PodGpsMode.acquiring) {
      _scheduleStale();
    }
    if (kDebugMode) debugPrint('PodLocationService: released');
  }

  // ── forceRefresh ────────────────────────────────────────────
  Future<void> forceRefresh() async {
    _cancelTimers();
    _gpsEngine.reset();
    _geocodeDone    = false;
    // FIX: null-kan koordinat geocode terakhir agar pergerakan <80m pun
    // tetap men-trigger geocode baru setelah user eksplisit minta refresh.
    _lastGeocodeLat = null;
    _lastGeocodeLon = null;
    _lockedAt       = null;
    await _startAcquire();
  }

  // ── dispose ─────────────────────────────────────────────────
  void dispose() {
    _cancelTimers();
    _stopStream();
    _stateCtrl.close();
    PodAddressResolver.close();
    _gpsEngine.dispose();
  }

  // ── INTERNAL: start acquire ──────────────────────────────────

  Future<void> _startAcquire() async {
    _stopStream();
    _gpsEngine.reset();
    _cancelTimers();

    _emit(currentState.copyWith(
      confidence:   PodConfidence.searching,
      lockProgress: 0.0,
      mode:         PodGpsMode.acquiring,
    ));

    // Inject OS cached position → instant preview
    try {
      final osLast = await Geolocator.getLastKnownPosition();
      if (osLast != null && !osLast.isMocked) {
        _gpsEngine.processSample(osLast);
        _emit(currentState.copyWith(
          lat:          osLast.latitude,
          lon:          osLast.longitude,
          accuracy:     osLast.accuracy,
          confidence:   _gpsEngine.confidence,
          lockProgress: _gpsEngine.lockProgress,
          isFallbackLock: _gpsEngine.isFallbackLock,
          mode:         PodGpsMode.acquiring,
        ));
        if (kDebugMode) {
          debugPrint('PodLocationService: OS lastKnown injected '
              'acc=${osLast.accuracy.toStringAsFixed(1)}m');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: getLastKnownPosition error $e');
    }

    // Fetch weather paralel
    final s = currentState;
    if (s.lat != null && s.lon != null && _weatherStale()) {
      unawaited(_updateWeather(s.lat!, s.lon!));
    }

    // Start GPS stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: PodGpsEngine.distanceFilterAcquiring.toInt(),
        forceLocationManager: false,
      ),
    ).listen(_onPosition, onError: (e) {
      if (kDebugMode) debugPrint('PodLocationService: stream error $e');
    });

    _acquireTimeout = Timer(_acquireDeadline, _onAcquireTimeout);

    if (kDebugMode) debugPrint('PodLocationService: acquiring started');
  }

  void _onAcquireTimeout() {
    if (currentState.mode != PodGpsMode.acquiring) return;
    if (kDebugMode) debugPrint('PodLocationService: acquire timeout — force stop');
    _stopStream();
    _emit(currentState.copyWith(
      mode: currentState.confidence.canCapture
          ? PodGpsMode.locked
          : PodGpsMode.stale,
    ));
    if (currentState.confidence.canCapture) _scheduleStale();
  }

  // ── INTERNAL: position handler ───────────────────────────────

  void _onPosition(Position raw) async {
    if (currentState.mode != PodGpsMode.acquiring) return;

    if (raw.isMocked) {
      _stopStream();
      _emit(currentState.copyWith(
        confidence: PodConfidence.poor,
        address:    'GPS Mock terdeteksi',
        mode:       PodGpsMode.idle,
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
      mode:           PodGpsMode.acquiring,
    ));

    // Geocode: canCapture pertama kali ATAU bergerak > _geocodeMoveM
    final movedFar = _geocodeDone &&
        _lastGeocodeLat != null &&
        PodGpsEngine.haversinePublic(
            _lastGeocodeLat!, _lastGeocodeLon!, lat, lon) > _geocodeMoveM;

    if ((!_geocodeDone && conf.canCapture) || movedFar) {
      _geocodeDone    = true;
      _lastGeocodeLat = lat;
      _lastGeocodeLon = lon;
      unawaited(_geocode(lat, lon));
    }

    if (upgraded && _weatherStale()) {
      unawaited(_updateWeather(lat, lon));
    }

    // Locked → stop stream
    if (_gpsEngine.isLocked) {
      _cancelTimers();
      _stopStream();
      _lockedAt = DateTime.now();
      _emit(currentState.copyWith(mode: PodGpsMode.locked));
      _scheduleStale();
      if (kDebugMode) {
        debugPrint('PodLocationService: locked acc=${acc.toStringAsFixed(1)}m');
      }
    }
  }

  // ── Stale timer ─────────────────────────────────────────────

  void _scheduleStale() {
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleAfter, () {
      if (currentState.mode == PodGpsMode.locked) {
        _emit(currentState.copyWith(mode: PodGpsMode.stale));
        if (kDebugMode) debugPrint('PodLocationService: lock stale after $_staleAfter');
      }
    });
  }

  // ── Geocode ──────────────────────────────────────────────────

  Future<void> _geocode(double lat, double lon) async {
    final key = _gridKey(lat, lon);
    if (_geocodeCache.containsKey(key)) {
      _emit(currentState.copyWith(
        address:        _geocodeCache[key]!,
        fromCache:      true,
        addressLoading: false,
      ));
      return;
    }

    _emit(currentState.copyWith(addressLoading: true));
    try {
      final resolved = await PodAddressResolver.resolveDetailed(lat, lon);
      final address = resolved.display;
      if (address.isNotEmpty && !resolved.isDmsFallback) {
        _geocodeCache[key] = address;
        if (_geocodeCache.length > _maxCache) {
          final remove = _geocodeCache.keys.take(50).toList();
          for (final k in remove) _geocodeCache.remove(k);
        }
        await _saveLastKnown(lat, lon, address);
      }
      _emit(currentState.copyWith(
        address:          address,
        resolvedLocation: resolved,
        fromCache:        false,
        addressLoading:   false,
        isFastAddress:    false,
      ));
      if (kDebugMode) debugPrint('PodLocationService: geocode → $address');
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: geocode error $e');
      _emit(currentState.copyWith(addressLoading: false));
    }
  }

  // ── Weather ──────────────────────────────────────────────────

  bool _weatherStale() {
    if (_lastWeatherAt == null) return true;
    return DateTime.now().difference(_lastWeatherAt!) > _weatherMaxAge;
  }

  Future<void> _updateWeather(double lat, double lon) async {
    try {
      final w = await _weatherService.fetchWeather(lat, lon);
      _emit(currentState.copyWith(weather: w));
      _lastWeatherAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: weather error $e');
    }
  }

  // ── Cache load/save ──────────────────────────────────────────

  Future<void> _loadCachedState() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final lat     = prefs.getDouble(_prefLat);
      final lon     = prefs.getDouble(_prefLon);
      final address = prefs.getString(_prefAddress);

      if (lat != null && lon != null && address != null && address.isNotEmpty) {
        final key = _gridKey(lat, lon);
        _geocodeCache[key] = address;
        _geocodeDone    = true;
        _lastGeocodeLat = lat;
        _lastGeocodeLon = lon;

        _emit(currentState.copyWith(
          lat:           lat,
          lon:           lon,
          address:       address,
          fromCache:     true,
          isFastAddress: true,
          confidence:    PodConfidence.fair,
          mode:          PodGpsMode.stale,
        ));
        if (kDebugMode) debugPrint('PodLocationService: cache loaded → $address');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PodLocationService: load cache error $e');
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
      if (kDebugMode) debugPrint('PodLocationService: save error $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  Future<bool> _checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm != LocationPermission.denied &&
           perm != LocationPermission.deniedForever;
  }

  void _stopStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _cancelTimers() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _acquireTimeout?.cancel();
    _acquireTimeout = null;
  }

  String _gridKey(double lat, double lon) {
    final gLat = (lat * _gridRes).round();
    final gLon = (lon * _gridRes).round();
    return '$gLat,$gLon';
  }

  void _emit(PodLocationState state) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(state);
  }
}
