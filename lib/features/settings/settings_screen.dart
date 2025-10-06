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
          ],
        ),
      ),
    );
  }
}
