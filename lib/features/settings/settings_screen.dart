import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../service/providers/settings_provider.dart';
import '../../theme/colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentInterval = ref.watch(gpsIntervalProvider);
    final trackingAsync = ref.watch(trackingLogsProvider);
    final checkInOutAsync = ref.watch(checkInOutLogsProvider);
    final localDbAsync = ref.watch(localDbLogsProvider);
    final versionAsync = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'App Settings',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: TWCColors.coffeeDark,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white), // ✅ makes back arrow white
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
                  const Text(
                    'Data collection every',
                    style: TextStyle(fontSize: 16),
                  ),
                  Text(
                    '$currentInterval seconds',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This value is fixed by the system. Drivers cannot change it.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),

            // 🔹 Section 1 — Tracking Logs
            const SizedBox(height: 16),

            // 🔹 Section 0 — Local SQLite Records
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
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: TWCColors.coffeeDark,
                  onPressed: () => ref.invalidate(localDbLogsProvider),
                ),
              ],
            ),
            Expanded(
              flex: 1,
              child: localDbAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('No local records'));
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final status = (e['status'] ?? 'pending') as String;
                      Color statusColor;
                      switch (status) {
                        case 'sent':
                          statusColor = Colors.green;
                          break;
                        case 'pending':
                        default:
                          statusColor = Colors.orange;
                      }
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
                loading: () =>
                const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
            const SizedBox(height: 20),

            // 🔹 Section 2 — Check-In / Check-Out Logs
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
              flex: 1,
              child: checkInOutAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('No check-in/out data'));
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final wh = e['warehouse_name'] ?? e['store_name'] ?? '-';
                      final locType = e['location_type'] ?? '—';
                      final status = e['trip_status'] ?? '';
                      final time = e['timestamp'] ?? '';
                      return ListTile(
                        leading: Icon(
                          status == 'in_progress' ? Icons.play_arrow_rounded : Icons.stop_circle_outlined,
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
            const SizedBox(height: 12),
            versionAsync.when(
              data: (v) => Center(
                child: Text(
                  'Version $v',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
