import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:untitled/service/providers/auth_provider.dart';
import 'package:untitled/service/providers/location_provider.dart';
import 'package:untitled/service/providers/settings_provider.dart';
import 'local_db_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final networkMonitorProvider =
Provider<NetworkMonitor>((ref) => NetworkMonitor(ref));

class NetworkMonitor {
  final Ref ref;
  late final StreamSubscription _sub;
  bool _isSyncing = false;
  Duration _retryDelay = const Duration(seconds: 30);

  NetworkMonitor(this.ref) {
    _sub = Connectivity().onConnectivityChanged.listen(_onStatusChange);
  }

  Future<void> _onStatusChange(List<ConnectivityResult> results) async {
    final hasNet = results.contains(ConnectivityResult.mobile) ||
        results.contains(ConnectivityResult.wifi);
    if (hasNet && !_isSyncing) {
      _isSyncing = true;
      await _tryResendWithBackoff();
      _isSyncing = false;
    }
  }

  /// Retry with exponential backoff
  Future<void> _tryResendWithBackoff() async {
    var attempts = 0;
    while (attempts < 5) {
      final success = await _syncLocalRecords();
      if (success) {
        _retryDelay = const Duration(seconds: 30);
        break;
      }
      attempts++;
      _retryDelay *= 2; // exponential backoff
      await Future.delayed(_retryDelay);
    }
  }

  /// Sync all locally stored records
  Future<bool> _syncLocalRecords() async {
    // ✅ prevent double sync if LocationNotifier is already syncing
    final currentStatus = ref.read(syncStatusProvider);
    if (currentStatus == SyncStatus.syncing) return true;

    final pending = await LocalDbService.getPendingRecords();
    if (pending.isEmpty) return true;

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;

    final api = ref.read(apiServiceProvider);

    try {
      final payload = pending.map<Map<String, dynamic>>((row) {
        return {
          'driver_id': row['driver_id'],
          'device_id': row['device_id'],
          'timestamp': row['timestamp'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'accuracy': row['accuracy'],
          'battery_level': row['battery_level'],
        };
      }).toList();

      await api.sendLocationBatch(payload);

      final ids = pending.map<int>((e) => e['id'] as int).toList();
      await LocalDbService.markRecordsSent(ids);

      // ✅ refresh UI status
      ref.invalidate(localDbLogsProvider);

      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      debugPrint("✅ Synced ${pending.length} offline records (kept in DB as SENT)");
      return true;
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;
      debugPrint("⚠️ Sync failed: $e");
      return false;
    }
  }

  void dispose() => _sub.cancel();
}
