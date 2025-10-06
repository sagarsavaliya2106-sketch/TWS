import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:untitled/service/local_db_service.dart';
import '../../features/location/location_record.dart';
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

  double _speedKmhFrom(Position pos) {
    // Prefer platform-provided speed (m/s) when available
    final s = pos.speed; // m/s, may be -1 or 0 on some devices
    if (s.isFinite && s >= 0) {
      final kmh = s * 3.6;
      if (kmh > 0) return kmh;
    }

    // Fallback: distance / time between last sample and current (m / s -> km/h)
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

  LocationNotifier(this.ref) : super(null) {
    // ✅ Auto restart tracking if interval changes
    ref.listen<int>(gpsIntervalProvider, (previous, next) async {
      if (_timer != null) {
        debugPrint("⚙️ Interval changed from $previous → $next seconds, restarting tracking...");
        final current = state;
        if (current != null) {
          await startLocationStream(
            employeeId: current.employeeId,
            deviceId: current.deviceId,
          );
        }
      }
    });
  }

  /// ✅ Immediately capture + periodically update location
  Future<void> startLocationStream({
    required String employeeId,
    required String deviceId,
  }) async {
    await stopLocationStream(); // Stop previous stream if any

    final interval = ref.read(gpsIntervalProvider);
    final duration = Duration(seconds: interval);
    final battery = Battery();

    debugPrint("🚀 GPS tracking started — collecting every $interval seconds");

    // ✅ Immediately capture one reading
    await _captureAndStoreLocation(employeeId, deviceId, battery);

    // ✅ Then start periodic timer
    _timer = Timer.periodic(duration, (_) async {
      await _captureAndStoreLocation(employeeId, deviceId, battery);
    });
  }

  /// ✅ Capture one reading and store in state
  Future<void> _captureAndStoreLocation(
      String employeeId,
      String deviceId,
      Battery battery,
      ) async {
    try {
      // 🎯 Choose accuracy dynamically
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
      debugPrint("🎚️ Using GPS accuracy: $_currentAccuracy");

      // 🚗 STEP 1 — compute current speed in km/h
      final speedKmh = _speedKmhFrom(pos);
      debugPrint("🚗 Current speed: ${speedKmh.toStringAsFixed(1)} km/h");

      // 🕒 Movement detection
      if (speedKmh > 5) {
        if (!_isMoving) {
          debugPrint("🏎️ Vehicle started moving — switching to HIGH accuracy mode");
          _isMoving = true;
          _stationarySince = null;
        }
      } else {
        if (_isMoving) {
          // Just became stationary
          _isMoving = false;
          _stationarySince = DateTime.now();
        } else {
          // Already stationary; check duration
          if (_stationarySince != null &&
              DateTime.now().difference(_stationarySince!).inMinutes >= 5) {
            debugPrint("🕯️ Stationary for 5+ minutes — switch to LOW POWER mode");
            // TODO: we'll apply low-power GPS settings in Step 2C
          }
        }
      }

      final batteryLevel = await battery.batteryLevel;

      final record = LocationRecord(
        employeeId: employeeId,
        deviceId: deviceId,
        timestamp: DateTime.now().toUtc(),
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        batteryLevel: batteryLevel.toDouble(),
      );

      // ✅ Update current provider state
      state = record;

      // ✅ Add record into batch buffer
      _batchBuffer.add(record);

      debugPrint("📍 Added to batch (${_batchBuffer.length} points): ${record.toJson()}");

      // ✅ Decide when to send
      final now = DateTime.now();
      final timeSinceLastSend = _lastSentAt == null
          ? 999999.0
          : now.difference(_lastSentAt!).inSeconds.toDouble();

      final shouldSend = _batchBuffer.length >= 10 || timeSinceLastSend >= 30;

      if (shouldSend) {
        debugPrint("🚀 Sending batch triggered (points=${_batchBuffer.length}, "
            "elapsed=${timeSinceLastSend.toStringAsFixed(1)}s)");
        await _sendBatchToServer();
      }

      // 🔁 Save last position for next speed calculation
      _lastPos = pos;
      _lastPosAt = DateTime.now();
    } catch (e) {
      debugPrint("⚠️ Location update error: $e");
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

      // ✅ Clear all synced records
      await LocalDbService.clearAll();

      // ✅ Then cleanup old (>2 days) data
      await LocalDbService.deleteOldRecords();
    } catch (e) {
      debugPrint("⚠️ Offline sync failed: $e");
    }
  }

  Future<void> _sendBatchToServer() async {
    if (_batchBuffer.isEmpty) return;

    // 🔄 1. Mark syncing
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final api = ref.read(apiServiceProvider);
      final batchJson = _batchBuffer.map((e) => e.toJson()).toList();

      debugPrint("📦 Sending batch of ${_batchBuffer.length} points to server...");

      await api.sendLocationBatch(batchJson);

      debugPrint("✅ Batch sent successfully (${_batchBuffer.length} points)");

      _batchBuffer.clear();
      _lastSentAt = DateTime.now();

      // 🔁 Try syncing any offline data (if available)
      await _syncOfflineRecords();

      // ✅ 2. Back to idle after success
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } catch (e) {
      debugPrint("⚠️ Network failed, storing ${_batchBuffer.length} points locally: $e");

      // ❗ Mark offline
      ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;

      // ✅ Save all points locally
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
      debugPrint("📤 Shift ended — sending remaining ${_batchBuffer.length} points...");
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
