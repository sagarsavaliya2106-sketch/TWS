import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:untitled/service/providers/auth_provider.dart';
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
    final pending = await LocalDbService.getAllRecords();
    if (pending.isEmpty) return true;

    final api = ref.read(apiServiceProvider);
    try {
      await api.sendLocationBatch(pending);
      await LocalDbService.clearAll();
      await LocalDbService.deleteOldRecords();
      debugPrint("✅ Synced ${pending.length} offline records");
      return true;
    } catch (e) {
      debugPrint("⚠️ Sync failed: $e");
      return false;
    }
  }

  void dispose() => _sub.cancel();
}
