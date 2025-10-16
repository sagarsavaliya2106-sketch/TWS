import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

final trackingLogsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authNotifierProvider);
  final mobile = auth.mobile;

  if (mobile == null || mobile.isEmpty) {
    return [];
  }

  return await api.fetchTrackingLogs(mobile);
});

/// Controls how frequently GPS is collected (in seconds)
final gpsIntervalProvider = StateProvider<int>((ref) => 15);
