import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../features/location/location_record.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

final locationProvider =
StateNotifierProvider<LocationNotifier, LocationRecord?>((ref) {
  return LocationNotifier(ref);
});

class LocationNotifier extends StateNotifier<LocationRecord?> {
  final Ref ref;
  Timer? _timer;

  final List<LocationRecord> _batchBuffer = [];
  DateTime? _lastSentAt;

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

    } catch (e) {
      debugPrint("⚠️ Location update error: $e");
    }
  }

  Future<void> _sendBatchToServer() async {
    if (_batchBuffer.isEmpty) return;

    try {
      // ✅ read ApiService instance from provider
      final api = ref.read(apiServiceProvider);

      // ✅ convert our LocationRecord objects to JSON
      final batchJson = _batchBuffer.map((e) => e.toJson()).toList();

      debugPrint("📦 Sending batch of ${_batchBuffer.length} points to server...");

      // ✅ call the method we just added in ApiService
      await api.sendLocationBatch(batchJson);

      debugPrint("✅ Batch sent successfully (${_batchBuffer.length} points)");

      // ✅ clear buffer + reset timer
      _batchBuffer.clear();
      _lastSentAt = DateTime.now();
    } catch (e) {
      debugPrint("⚠️ Failed to send batch: $e");
      // optional: you could keep the buffer for retry logic later
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
