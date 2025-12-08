import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:untitled/features/location/location_record.dart';
import 'package:untitled/service/local_db_service.dart';
import 'auth_provider.dart';       // for apiServiceProvider
import 'settings_provider.dart';  // for gpsIntervalProvider

enum SyncStatus {
  idle,      // nothing pending
  syncing,   // currently sending batch
  offline,   // last sync failed (pending in DB)
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

  LocationNotifier(this.ref) : super(null) {
    // If interval ever changes (even if fixed now), restart tracking.
    ref.listen<int>(gpsIntervalProvider, (previous, next) async {
      if (_positionSub != null) {
        debugPrint(
          "⚙️ Interval changed from $previous → $next seconds, restarting tracking...",
        );
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

    final interval = ref.read(gpsIntervalProvider); // fixed 10s
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
      final now = DateTime.now();

      // ⏱️ Enforce MINIMUM 10 seconds between saved records
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

      // Use stream position if provided, otherwise get one shot (fallback)
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
        timestamp: now,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        batteryLevel: batteryLevel.toDouble(),
      );

      // ✅ Update provider state (UI shows latest)
      state = record;

      // ✅ ALWAYS store to local DB as pending
      await LocalDbService.insertRecord(record.toJson(), status: 'pending');
      debugPrint("📍 Stored to local DB: ${record.toJson()}");

      // 🔄 Tell Settings screen to reload local DB list
      ref.invalidate(localDbLogsProvider);

      // ✅ Try to sync any pending records
      await _trySyncPending();

      // 🧭 Save last position & time for next check
      _lastPos = pos;
      _lastPosAt = now;
    } catch (e) {
      debugPrint("⚠️ Location capture error: $e");
    }
  }

  /// Read all pending records from SQLite and send them when:
  /// - we have AT LEAST 3 pending records
  /// - we are not already syncing
  Future<void> _trySyncPending() async {
    final currentStatus = ref.read(syncStatusProvider);
    if (currentStatus == SyncStatus.syncing) {
      return; // avoid parallel syncs
    }

    final pending = await LocalDbService.getPendingRecords();
    if (pending.length < 3) {
      debugPrint(
          "⌛ Pending records below threshold (have ${pending.length}, need >= 3)");
      return;
    }

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    try {
      final api = ref.read(apiServiceProvider);

      final payload = pending.map<Map<String, dynamic>>((row) {
        return {
          'driver_id': row['employee_id'],
          'device_id': row['device_id'],
          'timestamp': row['timestamp'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'accuracy': row['accuracy'],
          'battery_level': row['battery_level'],
        };
      }).toList();

      debugPrint("📦 Syncing ${pending.length} pending records to server...");
      await api.sendLocationBatch(payload);
      debugPrint("✅ Synced ${pending.length} records");

      final ids = pending
          .map<int>((row) => row['id'] as int)
          .toList();
      await LocalDbService.markRecordsSent(ids);

      // 🔄 Refresh local DB list so statuses change from PENDING → SENT
      ref.invalidate(localDbLogsProvider);

      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } catch (e) {
      debugPrint("⚠️ Sync failed, will retry later: $e");
      ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;
    }
  }

  Future<void> stopLocationStream() async {
    await _positionSub?.cancel();
    _positionSub = null;

    // Try one more time to sync anything still pending
    await _trySyncPending();
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