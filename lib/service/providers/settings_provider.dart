import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:untitled/service/local_db_service.dart';
import 'auth_provider.dart';

final trackingLogsProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authNotifierProvider);
  final mobile = auth.mobile;
  if (mobile == null || mobile.isEmpty) return [];
  return await api.fetchTrackingLogs(mobile);
});

final checkInOutLogsProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authNotifierProvider);
  final mobile = auth.mobile;
  if (mobile == null || mobile.isEmpty) return [];
  return await api.fetchCheckInOutLogs(mobile);
});

/// New: Local SQLite logs (pending + sent)
final localDbLogsProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await LocalDbService.getAllRecords();
});

/// Fixed GPS interval (seconds)
final gpsIntervalProvider = StateProvider<int>((ref) => 10);