class LocationRecord {
  final String driverId;
  final String deviceId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double batteryLevel;

  LocationRecord({
    required this.driverId,
    required this.deviceId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.batteryLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'driver_id': driverId,
      'device_id': deviceId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'battery_level': batteryLevel,
    };
  }
}
