import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'location_record.dart';

final locationProvider = StateNotifierProvider<LocationNotifier, LocationRecord?>((ref) {
  return LocationNotifier();
});

class LocationNotifier extends StateNotifier<LocationRecord?> {
  LocationNotifier() : super(null);

  final _battery = Battery();
  StreamSubscription<Position>? _sub;

  Future<void> fetchCurrentLocation({
    required String employeeId,
    required String deviceId,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied.');
    }

    final settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      timeLimit: const Duration(seconds: 15),
    );

    final pos = await Geolocator.getCurrentPosition(locationSettings: settings);
    final battery = await _battery.batteryLevel;

    state = LocationRecord(
      employeeId: employeeId,
      deviceId: deviceId,
      timestamp: DateTime.now().toUtc(),
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      batteryLevel: battery.toDouble(),
    );
  }

  Future<void> startLocationStream({
    required String employeeId,
    required String deviceId,
  }) async {
    await _sub?.cancel();

    final settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 10, // update every 10 meters
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (pos) async {
        final battery = await _battery.batteryLevel;
        state = LocationRecord(
          employeeId: employeeId,
          deviceId: deviceId,
          timestamp: DateTime.now().toUtc(),
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          batteryLevel: battery.toDouble(),
        );
      },
      onError: (e) {},
    );
  }

  Future<void> stopLocationStream() async {
    await _sub?.cancel();
    _sub = null;
  }

  void clearLocation() {
    state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
