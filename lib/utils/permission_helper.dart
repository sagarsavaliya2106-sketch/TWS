import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<bool> ensureLocationPermission(BuildContext context) async {
  // First check if GPS service is enabled
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
    return false;
  }

  // Then check app-level permission
  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Location Permission Required"),
          content: const Text(
            "Location permission is permanently denied. "
                "Please enable it from Settings to continue tracking.",
          ),
          actions: [
            TextButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: const Text("Open Settings"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
          ],
        ),
      );
    }
    return false;
  }

  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}
