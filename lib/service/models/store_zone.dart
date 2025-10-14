class StoreZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double? radiusMeters; // nullable until backend sends it

  const StoreZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.radiusMeters,
  });

  factory StoreZone.fromJson(Map<String, dynamic> j) {
    // Tolerant parsing
    final idVal = j['id'] ?? j['store_id'] ?? j['zoneId'] ?? j['zone_id'];
    final nameVal = j['store_name'] ?? j['name'] ?? 'Unknown';
    final latVal = (j['latitude'] as num?)?.toDouble() ?? 0.0;
    final lngVal = (j['longitude'] as num?)?.toDouble() ?? 0.0;

    // If backend later adds 'radius' (meters)
    final r = (j['radius'] as num?)?.toDouble();

    return StoreZone(
      id: '$idVal',
      name: nameVal.toString(),
      lat: latVal,
      lng: lngVal,
      radiusMeters: r, // may be null for now
    );
  }

  bool get hasValidCenter => lat != 0.0 || lng != 0.0;
}
