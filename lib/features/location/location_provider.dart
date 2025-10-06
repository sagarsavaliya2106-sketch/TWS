import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationProvider = StateNotifierProvider<LocationNotifier, Position?>((ref) {
  return LocationNotifier();
});

class LocationNotifier extends StateNotifier<Position?> {
  LocationNotifier() : super(null);

  StreamSubscription<Position>? _sub;

  /// Request permission + fetch one-time current position
  Future<void> fetchCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Please enable it from settings.');
    }

    final settings = LocationSettings(
      accuracy: LocationAccuracy.best, // most precise
      distanceFilter: 0, // every movement triggers an update
      timeLimit: const Duration(seconds: 15),
    );

    final pos = await Geolocator.getCurrentPosition(locationSettings: settings);
    state = pos;
  }

  /// Start continuous stream updates
  Future<void> startLocationStream() async {
    // Cancel existing stream if any
    await _sub?.cancel();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
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
      distanceFilter: 10, // updates every 10 meters
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (Position pos) {
        state = pos;
      },
      onError: (e) {
        // ignore errors silently
      },
    );
  }

  void clearLocation() {
    state = null;
  }

  /// Stop live location updates
  Future<void> stopLocationStream() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
