import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:untitled/service/providers/settings_provider.dart';

import 'local_db_service.dart';

class TrackingHealth {
  final bool isOk;
  final String message;
  final DateTime? lastSavedAt;

  TrackingHealth({required this.isOk, required this.message, this.lastSavedAt});
}

final trackingHealthProvider = StreamProvider<TrackingHealth>((ref) async* {
  final interval = ref.watch(gpsIntervalProvider);
  final threshold = Duration(seconds: interval * 6);

  while (true) {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      yield TrackingHealth(
        isOk: false,
        message: "Location is OFF. Turn ON location to continue tracking.",
      );
      await Future.delayed(const Duration(seconds: 3));
      continue;
    }

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      yield TrackingHealth(
        isOk: false,
        message: "Location permission is denied. Please allow permission.",
      );
      await Future.delayed(const Duration(seconds: 3));
      continue;
    }

    final latest = await LocalDbService.getLatestRecord();
    final last = _tryParseTimestamp(latest?['timestamp']?.toString());

    if (last == null) {
      yield TrackingHealth(isOk: false, message: "No GPS records saved yet.");
    } else {
      final diff = DateTime.now().difference(last);
      if (diff > threshold) {
        yield TrackingHealth(
          isOk: false,
          message: "GPS tracking looks stopped. Last saved ${diff.inSeconds}s ago.",
          lastSavedAt: last,
        );
      } else {
        yield TrackingHealth(isOk: true, message: "GPS tracking is running.", lastSavedAt: last);
      }
    }

    await Future.delayed(const Duration(seconds: 5));
  }
});

// reuse the same parser you already used earlier
DateTime? _tryParseTimestamp(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final direct = DateTime.tryParse(s);
  if (direct != null) return direct;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
  return null;
}