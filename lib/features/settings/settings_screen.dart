import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../service/providers/settings_provider.dart';
import '../../widgets/twc_toast.dart';
import '../../theme/colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentInterval = ref.watch(gpsIntervalProvider);
    final trackingAsync = ref.watch(trackingLogsProvider);
    final checkInOutAsync = ref.watch(checkInOutLogsProvider);

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
            DropdownButtonFormField<int>(
              value: currentInterval,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 seconds')),
                DropdownMenuItem(value: 15, child: Text('15 seconds (Default)')),
                DropdownMenuItem(value: 20, child: Text('20 seconds')),
                DropdownMenuItem(value: 30, child: Text('30 seconds')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                ref.read(gpsIntervalProvider.notifier).state = v;
                showTwcToast(context, 'GPS interval updated to $v seconds');
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The app will now collect GPS data every $currentInterval seconds.',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 28),

            // 🔹 Section 1 — Tracking Logs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Latest Tracking Logs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: TWCColors.coffeeDark,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: TWCColors.coffeeDark,
                  onPressed: () => ref.invalidate(trackingLogsProvider),
                ),
              ],
            ),
            Expanded(
              flex: 1,
              child: trackingAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(child: Text('No tracking data'));
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final e = list[i];
                      return ListTile(
                        title: Text(e['timestamp'] ?? ''),
                        subtitle: Text(
                          'Lat: ${e['latitude']}, Lon: ${e['longitude']}\n'
                              'Acc: ${e['accuracy']}m, battery_level: ${e['battery_level']}%',
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
          ],
        ),
      ),
    );
  }
}
