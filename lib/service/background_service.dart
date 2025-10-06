import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import '../service/local_db_service.dart';
import '../features/location/location_record.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Configure background service
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'location_service',
      initialNotificationTitle: 'TWC Tracker Active',
      initialNotificationContent: 'Collecting GPS in background',
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      autoStart: false,
      onBackground: onIosBackground,
    ),
  );

  // Optional: ensure old instance stops (safe restart)
  if (await service.isRunning()) {
    debugPrint("🛑 Stopping old background service...");
    service.invoke("stopService");
  }

  debugPrint("✅ Background service initialized");
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // Required for iOS background fetch
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Listen for stop request
  service.on('stopService').listen((event) {
    debugPrint("🛑 Service stopped manually");
    service.stopSelf();
  });

  final battery = Battery();

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final batteryLevel = await battery.batteryLevel;

      final record = LocationRecord(
        employeeId: "1",
        deviceId: "BACKGROUND",
        timestamp: DateTime.now().toUtc(),
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        batteryLevel: batteryLevel.toDouble(),
      );

      debugPrint("📍 BG location: ${record.toJson()}");
      await LocalDbService.insertRecord(record.toJson());
    }
  });
}
