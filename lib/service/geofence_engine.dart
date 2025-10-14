import 'package:geolocator/geolocator.dart';
import 'models/store_zone.dart';

typedef GeofenceEnter = Future<void> Function(StoreZone zone, Position pos);
typedef GeofenceExit  = Future<void> Function(StoreZone zone, Position pos);

class GeofenceEngine {
  GeofenceEngine({
    required this.onEnter,
    required this.onExit,
    this.exitHysteresisFactor = 1.10, // 10% bigger to avoid flapping
    this.minDwellInsideMs = 4000,     // stay inside for >= 4s before enter
    this.minDwellOutsideMs = 6000,    // stay outside for >= 6s before exit
    this.apiCooldownMs = 20000,       // don’t call server too often
    this.defaultRadiusMeters = 100,   // used if zone.radiusMeters == null
  });

  final GeofenceEnter onEnter;
  final GeofenceExit onExit;

  final double exitHysteresisFactor;
  final int minDwellInsideMs;
  final int minDwellOutsideMs;
  final int apiCooldownMs;
  final double defaultRadiusMeters;

  List<StoreZone> _zones = [];
  StoreZone? _active;
  DateTime _lastEnter = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastExit  = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _enteredAt;
  DateTime? _leftAt;

  void setZones(List<StoreZone> zones) {
    _zones = zones.where((z) => z.hasValidCenter).toList();
  }

  Future<void> onLocation(Position pos) async {
    if (_zones.isEmpty) return;

    // nearest zone
    StoreZone? nearest;
    double best = double.infinity;
    for (final z in _zones) {
      final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, z.lat, z.lng);
      if (d < best) {
        best = d;
        nearest = z;
      }
    }
    if (nearest == null) return;

    final radius = nearest.radiusMeters ?? defaultRadiusMeters;
    if (radius <= 0) return; // skip until backend sends radius / default

    final inRadius = best <= radius;
    final exitThreshold = radius * exitHysteresisFactor;
    final now = DateTime.now();

    if (_active == null) {
      if (inRadius) {
        _enteredAt ??= now;
        if (now.difference(_enteredAt!).inMilliseconds >= minDwellInsideMs &&
            now.difference(_lastEnter).inMilliseconds >= apiCooldownMs) {
          _active = nearest;
          _enteredAt = null;
          _leftAt = null;
          _lastEnter = now;
          await onEnter(_active!, pos);
        }
      } else {
        _enteredAt = null;
      }
    } else {
      // we are inside an active zone
      final dActive = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, _active!.lat, _active!.lng,
      );
      if (dActive > exitThreshold) {
        _leftAt ??= now;
        if (now.difference(_leftAt!).inMilliseconds >= minDwellOutsideMs &&
            now.difference(_lastExit).inMilliseconds >= apiCooldownMs) {
          final leaving = _active!;
          _active = null;
          _enteredAt = null;
          _leftAt = null;
          _lastExit = now;
          await onExit(leaving, pos);
        }
      } else {
        _leftAt = null;
      }
    }
  }
}
