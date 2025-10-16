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

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
        backgroundColor: TWCColors.coffeeDark,
        centerTitle: true,
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
                  onPressed: () {
                    ref.invalidate(trackingLogsProvider);
                  },
                ),
              ],
            ),

            Expanded(
              child: trackingAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('No tracking data available',
                          style: TextStyle(color: Colors.black54)),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final item = list[i];
                      final time = item['timestamp'] ?? '';
                      final lat = item['latitude'];
                      final lon = item['longitude'];
                      final acc = item['accuracy'];
                      final bat = item['battery_level'];

                      return ListTile(
                        title: Text(
                          '$time',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: TWCColors.coffeeDark,
                          ),
                        ),
                        subtitle: Text(
                          'Lat: $lat, Lon: $lon\nAccuracy: ${acc?.toStringAsFixed(1)}m, Battery: ${bat?.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                        ),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text(
                    'Failed to load logs\n$err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
