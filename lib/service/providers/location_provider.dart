import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:untitled/features/location/location_record.dart';
import 'package:untitled/service/local_db_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

enum SyncStatus {
  idle,      // nothing pending
  syncing,   // currently sending batch or retrying
  offline,   // storing locally because no network
}

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

final locationProvider =
StateNotifierProvider<LocationNotifier, LocationRecord?>((ref) {
  return LocationNotifier(ref);
});

class LocationNotifier extends StateNotifier<LocationRecord?> {
  final Ref ref;
  StreamSubscription<Position>? _positionSub;

  Position? _lastPos;
  DateTime? _lastPosAt;
  bool _isMoving = false;
  DateTime? _stationarySince;
  LocationAccuracy _currentAccuracy = LocationAccuracy.high;

  final List<LocationRecord> _batchBuffer = [];

  LocationNotifier(this.ref) : super(null) {
    // If interval ever changes in settings (even though it's fixed now),
    // restart tracking with the same driver/device.
    ref.listen<int>(gpsIntervalProvider, (previous, next) async {
      if (_positionSub != null) {
        debugPrint(
            "⚙️ Interval changed from $previous → $next seconds, restarting tracking...");
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

    final interval = ref.read(gpsIntervalProvider); // should be 10
    final battery = Battery();

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: _currentAccuracy,
        intervalDuration: Duration(seconds: interval),
        distanceFilter: 0,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Location tracking active',
          notificationText:
          'We are tracking your location while you are on duty.',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: _currentAccuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    debugPrint(
        "🚀 GPS tracking started via getPositionStream (interval=$interval s)");

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position? pos) async {
      if (pos == null) return;

      await _captureAndStoreLocation(
        driverId,
        deviceId,
        battery,
        externalPosition: pos,
      );
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
          _lastPos!.latitude,
          _lastPos!.longitude,
          pos.latitude,
          pos.longitude,
        );
        return (meters / seconds) * 3.6;
      }
    }
    return 0.0;
  }

  Future<void> _captureAndStoreLocation(
      String driverId,
      String deviceId,
      Battery battery, {
        Position? externalPosition,
      }) async {
    try {
      // ⏱️ Enforce MINIMUM 10 seconds between saved records
      final now = DateTime.now();
      if (_lastPosAt != null) {
        final diff = now.difference(_lastPosAt!).inSeconds;
        if (diff < 10) {
          debugPrint("⏱️ Skipping point: only ${diff}s since last sample");
          return;
        }
      }

      // 🔧 Adjust accuracy based on motion
      if (_isMoving) {
        _currentAccuracy = LocationAccuracy.bestForNavigation;
      } else if (_stationarySince != null &&
          DateTime.now().difference(_stationarySince!).inMinutes >= 5) {
        _currentAccuracy = LocationAccuracy.low;
      } else {
        _currentAccuracy = LocationAccuracy.high;
      }

      // Use stream position if provided, otherwise get one shot
      final pos = externalPosition ??
          await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: _currentAccuracy,
              timeLimit: const Duration(seconds: 10),
            ),
          );

      // 🚗 Compute speed and update motion state
      final speedKmh = _speedKmhFrom(pos);
      debugPrint("🚗 Current speed: ${speedKmh.toStringAsFixed(1)} km/h");

      if (speedKmh > 5) {
        if (!_isMoving) {
          debugPrint(
              "🏎️ Vehicle started moving — switching to HIGH accuracy");
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

      // 🔋 Battery level
      final batteryLevel = await battery.batteryLevel;

      // 📝 Build record
      final record = LocationRecord(
        driverId: driverId,
        deviceId: deviceId,
        timestamp: DateTime.now().toUtc(),
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        batteryLevel: batteryLevel.toDouble(),
      );

      // ✅ Update provider state
      state = record;

      // ✅ Add to batch
      _batchBuffer.add(record);
      debugPrint(
          "📍 Added to batch (${_batchBuffer.length}): ${record.toJson()}");

      // ✅ Decide when to send
      // We want: minimum 3 records per request.
      const recordsThreshold = 3;
      final shouldSend = _batchBuffer.length >= recordsThreshold;

      if (shouldSend) {
        debugPrint("🚀 Triggering send, batch has ${_batchBuffer.length} points");
        await _sendBatchToServer();
      }

      // 🧭 Save last position & time for next checks
      _lastPos = pos;
      _lastPosAt = now;
    } catch (e) {
      debugPrint("⚠️ Location capture error: $e");
    }
  }

  Future<void> _sendBatchToServer() async {
    if (_batchBuffer.isEmpty) return;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      // 1️⃣ Load previously unsent records from SQLite
      final offline = await LocalDbService.getAllRecords();

      // 2️⃣ Convert current in-memory batch to JSON
      final current = _batchBuffer.map((e) => e.toJson()).toList();

      // 3️⃣ Combine: old (offline) + new (current)
      final payload = <Map<String, dynamic>>[
        ...offline,
        ...current,
      ];

      if (payload.isEmpty) {
        debugPrint("ℹ️ Nothing to send (payload empty)");
        ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        return;
      }

      final api = ref.read(apiServiceProvider);
      debugPrint(
        "📦 Sending ${payload.length} points "
            "(offline=${offline.length}, current=${current.length})...",
      );

      // 4️⃣ Single call to /twc_driver/tracking
      await api.sendLocationBatch(payload);
      debugPrint("✅ Batch sent successfully");

      // 5️⃣ On success: clear everything and start fresh
      _batchBuffer.clear();
      await LocalDbService.clearAll();
      await LocalDbService.deleteOldRecords();

      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } catch (e) {
      debugPrint(
        "⚠️ Network failed — storing ${_batchBuffer.length} current points locally: $e",
      );
      ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;

      // 6️⃣ On failure: keep old offline data, just add CURRENT batch
      for (final record in _batchBuffer) {
        await LocalDbService.insertRecord(record.toJson());
      }

      _batchBuffer.clear();
    }
  }

  Future<void> stopLocationStream() async {
    await _positionSub?.cancel();
    _positionSub = null;

    if (_batchBuffer.isNotEmpty) {
      debugPrint(
          "📤 Stopping tracking — sending remaining ${_batchBuffer.length} points...");
      await _sendBatchToServer();
    }
  }

  void clearLocation() {
    state = null;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}