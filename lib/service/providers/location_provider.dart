import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:untitled/features/location/location_record.dart';
import 'package:untitled/service/local_db_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

enum SyncStatus {
  idle,        // nothing pending
  syncing,     // currently sending batch or retrying
  offline,     // storing locally because no network
}

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

final locationProvider =
StateNotifierProvider<LocationNotifier, LocationRecord?>((ref) {
  return LocationNotifier(ref);
});

class LocationNotifier extends StateNotifier<LocationRecord?> {
  final Ref ref;
  Timer? _timer;

  Position? _lastPos;
  DateTime? _lastPosAt;
  bool _isMoving = false;
  DateTime? _stationarySince;
  LocationAccuracy _currentAccuracy = LocationAccuracy.high;

  final List<LocationRecord> _batchBuffer = [];
  DateTime? _lastSentAt;

  LocationNotifier(this.ref) : super(null) {
    // ✅ Restart tracking if GPS interval changes dynamically
    ref.listen<int>(gpsIntervalProvider, (previous, next) async {
      if (_timer != null) {
        debugPrint("⚙️ Interval changed from $previous → $next seconds, restarting tracking...");
        final current = state;
        if (current != null) {
          await startLocationStream(
            driverId: current.driverId,
            deviceId: current.deviceId,
          );
        }
      }
    });
  }

  Future<void> startLocationStream({
    required String driverId,
    required String deviceId,
  }) async {
    await stopLocationStream();

    final interval = ref.read(gpsIntervalProvider);
    final duration = Duration(seconds: interval);
    final battery = Battery();

    debugPrint("🚀 GPS tracking started — collecting every $interval seconds");
    await _captureAndStoreLocation(driverId, deviceId, battery);

    _timer = Timer.periodic(duration, (_) async {
      await _captureAndStoreLocation(driverId, deviceId, battery);
    });
  }

  double _speedKmhFrom(Position pos) {
    final s = pos.speed; // m/s
    if (s.isFinite && s >= 0) {
      final kmh = s * 3.6;
      if (kmh > 0) return kmh;
    }
    if (_lastPos != null && _lastPosAt != null) {
      final seconds = DateTime.now().difference(_lastPosAt!).inSeconds;
      if (seconds > 0) {
        final meters = Geolocator.distanceBetween(
          _lastPos!.latitude, _lastPos!.longitude,
          pos.latitude, pos.longitude,
        );
        return (meters / seconds) * 3.6;
      }
    }
    return 0.0;
  }

  Future<void> _captureAndStoreLocation(
      String driverId,
      String deviceId,
      Battery battery,
      ) async {
    try {
      // 🔧 Adjust accuracy based on motion
      if (_isMoving) {
        _currentAccuracy = LocationAccuracy.bestForNavigation;
      } else if (_stationarySince != null &&
          DateTime.now().difference(_stationarySince!).inMinutes >= 5) {
        _currentAccuracy = LocationAccuracy.low;
      } else {
        _currentAccuracy = LocationAccuracy.high;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: _currentAccuracy,
          timeLimit: const Duration(seconds: 10),
        ),
      );

      final speedKmh = _speedKmhFrom(pos);
      debugPrint("🚗 Current speed: ${speedKmh.toStringAsFixed(1)} km/h");

      if (speedKmh > 5) {
        if (!_isMoving) {
          debugPrint("🏎️ Vehicle started moving — switching to HIGH accuracy");
          _isMoving = true;
          _stationarySince = null;
        }
      } else {
        if (_isMoving) {
          _isMoving = false;
          _stationarySince = DateTime.now();
        } else if (_stationarySince != null &&
            DateTime.now().difference(_stationarySince!).inMinutes >= 5) {
          debugPrint("🕯️ Stationary for 5+ min — low power mode");
        }
      }

      final batteryLevel = await battery.batteryLevel;

      final record = LocationRecord(
        driverId: driverId,
        deviceId: deviceId,
        timestamp: DateTime.now().toUtc(),
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        batteryLevel: batteryLevel.toDouble(),
      );

      // ✅ Update current provider state
      state = record;

      // ✅ Add to batch
      _batchBuffer.add(record);
      debugPrint("📍 Added to batch (${_batchBuffer.length}): ${record.toJson()}");

      // ✅ Decide when to send
      final now = DateTime.now();
      final timeSinceLastSend =
      _lastSentAt == null ? 999999.0 : now.difference(_lastSentAt!).inSeconds.toDouble();
      final shouldSend = _batchBuffer.length >= 10 || timeSinceLastSend >= 30;

      if (shouldSend) {
        debugPrint("🚀 Sending batch (${_batchBuffer.length} points, "
            "elapsed=${timeSinceLastSend.toStringAsFixed(1)}s)");
        await _sendBatchToServer();
      }

      _lastPos = pos;
      _lastPosAt = DateTime.now();
    } catch (e) {
      debugPrint("⚠️ Location capture error: $e");
    }
  }

  Future<void> _syncOfflineRecords() async {
    try {
      final pending = await LocalDbService.getAllRecords();
      if (pending.isEmpty) {
        debugPrint("🟢 No offline records to sync");
        return;
      }

      debugPrint("📤 Found ${pending.length} offline records — syncing...");
      final api = ref.read(apiServiceProvider);
      await api.sendLocationBatch(pending);
      debugPrint("✅ Synced ${pending.length} offline records");

      await LocalDbService.clearAll();
      await LocalDbService.deleteOldRecords();
    } catch (e) {
      debugPrint("⚠️ Offline sync failed: $e");
    }
  }

  Future<void> _sendBatchToServer() async {
    if (_batchBuffer.isEmpty) return;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final api = ref.read(apiServiceProvider);
      final batchJson = _batchBuffer.map((e) => e.toJson()).toList();

      debugPrint("📦 Sending ${_batchBuffer.length} points...");
      await api.sendLocationBatch(batchJson);
      debugPrint("✅ Batch sent successfully");

      _batchBuffer.clear();
      _lastSentAt = DateTime.now();

      await _syncOfflineRecords();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } catch (e) {
      debugPrint("⚠️ Network failed — storing ${_batchBuffer.length} locally: $e");
      ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;

      for (final record in _batchBuffer) {
        await LocalDbService.insertRecord(record.toJson());
      }

      _batchBuffer.clear();
      _lastSentAt = DateTime.now();
    }
  }

  Future<void> stopLocationStream() async {
    _timer?.cancel();
    _timer = null;

    if (_batchBuffer.isNotEmpty) {
      debugPrint("📤 Stopping tracking — sending remaining ${_batchBuffer.length} points...");
      await _sendBatchToServer();
    }
  }

  void clearLocation() {
    state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
