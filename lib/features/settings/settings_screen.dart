import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../service/providers/settings_provider.dart';
import '../../service/tracking_health.dart';
import '../../theme/colors.dart';
import 'local_gps_records_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentInterval = ref.watch(gpsIntervalProvider);
    final localDbAsync = ref.watch(localDbLogsProvider);
    final checkInOutAsync = ref.watch(checkInOutLogsProvider);
    final versionAsync = ref.watch(appVersionProvider);

    // ✅ watch health here (NOT inside onPressed)
    final healthAsync = ref.watch(trackingHealthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: TWCColors.coffeeDark,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: TWCColors.latteBg,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPS Data Collection Interval',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: TWCColors.coffeeDark,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Data collection every', style: TextStyle(fontSize: 16)),
                  Text(
                    '$currentInterval seconds',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This value is fixed by the system. Drivers cannot change it.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 14),

            // ✅ Tracking stopped banner (shows automatically)
            healthAsync.when(
              data: (h) {
                if (h.isOk) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          h.message,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            await Geolocator.openLocationSettings();
                            ref.invalidate(trackingHealthProvider);
                            return;
                          }

                          final perm = await Geolocator.checkPermission();
                          if (perm == LocationPermission.denied) {
                            await Geolocator.requestPermission();
                            ref.invalidate(trackingHealthProvider);
                            return;
                          }
                          if (perm == LocationPermission.deniedForever) {
                            await Geolocator.openAppSettings();
                            ref.invalidate(trackingHealthProvider);
                            return;
                          }

                          // Tracking stalled case: refresh health + records
                          ref.invalidate(localDbLogsProvider);
                          ref.invalidate(trackingHealthProvider);
                        },
                        child: const Text('Restart'),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // 🔹 Local SQLite Records header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Local stored GPS records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: TWCColors.coffeeDark,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      color: TWCColors.coffeeDark,
                      onPressed: () => ref.invalidate(localDbLogsProvider),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LocalGpsRecordsScreen()),
                        );
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
              ],
            ),

            // ✅ Small preview list (5 rows)
            SizedBox(
              height: 240,
              child: localDbAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('No local records'));
                  }

                  final preview = list.take(5).toList();
                  return ListView.separated(
                    itemCount: preview.length,
                    separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final e = preview[i];
                      final status = (e['status'] ?? 'pending') as String;
                      final statusColor =
                      status == 'sent' ? Colors.green : Colors.orange;

                      return ListTile(
                        title: Text(e['timestamp'] ?? ''),
                        subtitle: Text(
                          'Lat: ${e['latitude']}, Lon: ${e['longitude']}\n'
                              'Acc: ${e['accuracy']}m, Battery: ${e['battery_level']}%',
                          style: const TextStyle(height: 1.3),
                        ),
                        trailing: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        dense: true,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),

            const SizedBox(height: 16),

            // 🔹 Check-In / Check-Out Logs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Latest Check-In Logs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: TWCColors.coffeeDark,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: TWCColors.coffeeDark,
                  onPressed: () => ref.invalidate(checkInOutLogsProvider),
                ),
              ],
            ),
            Expanded(
              child: checkInOutAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('No check-in/out data'));
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final wh = e['warehouse_name'] ?? e['store_name'] ?? '-';
                      final locType = e['location_type'] ?? '—';
                      final status = e['trip_status'] ?? '';
                      final time = e['timestamp'] ?? '';

                      return ListTile(
                        leading: Icon(
                          status == 'in_progress'
                              ? Icons.play_arrow_rounded
                              : Icons.stop_circle_outlined,
                          color: status == 'in_progress'
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        title: Text('$locType: $wh'),
                        subtitle: Text(
                          'Status: $status\nTime: $time\nLat: ${e['latitude']}, Lon: ${e['longitude']}',
                          style: const TextStyle(height: 1.3),
                        ),
                        dense: true,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),

            const SizedBox(height: 10),
            versionAsync.when(
              data: (v) => Center(
                child: Text('Version $v',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              loading: () => const Center(
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}