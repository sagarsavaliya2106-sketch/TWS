import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../features/location/location_record.dart';
import 'settings_provider.dart';

final locationProvider =
StateNotifierProvider<LocationNotifier, LocationRecord?>((ref) {
  return LocationNotifier(ref);
});

class LocationNotifier extends StateNotifier<LocationRecord?> {
  final Ref ref;
  Timer? _timer;

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
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );

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

      state = record; // ✅ update provider state

      debugPrint("📡 Location stored in state: ${record.toJson()}");
    } catch (e) {
      debugPrint("⚠️ Location update error: $e");
    }
  }

  Future<void> stopLocationStream() async {
    _timer?.cancel();
    _timer = null;
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
