import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/features/auth/login_screen.dart';
import 'package:untitled/features/settings/settings_screen.dart';
import 'package:untitled/service/providers/auth_provider.dart';
import 'package:untitled/service/providers/location_provider.dart';
import 'package:untitled/service/providers/attendance_ui_provider.dart';
import '../../theme/colors.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isLoading = false;

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveAttendanceToPrefs(bool checkedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isCheckedIn', checkedIn);
  }

  Future<bool> _restoreCheckedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isCheckedIn') ?? false;
  }

  // 🔹 NEW: persist duty toggle
  Future<void> _saveDutyToPrefs(bool dutyOn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDutyOn', dutyOn);
  }

  Future<bool> _restoreDuty() async {
    final prefs = await SharedPreferences.getInstance();
    // default = true when checked-in (auto ON like Rapido)
    return prefs.getBool('isDutyOn') ?? true;
  }

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  Future<void> _restoreState() async {
    final checkedIn = await _restoreCheckedIn();
    final dutyOn = await _restoreDuty();
    if (!mounted) return;

    final uiNotifier = ref.read(attendanceUiProvider.notifier);
    uiNotifier.forceCheckedIn(checkedIn);

    // 🔹 NEW: restore duty switch
    final dutyNotifier = ref.read(dutyToggleProvider.notifier);
    final effectiveDutyOn = checkedIn && dutyOn;
    dutyNotifier.state = effectiveDutyOn;

    if (checkedIn && effectiveDutyOn) {
      final auth = ref.read(authNotifierProvider);
      final driverId = auth.mobile ?? 'unknown';
      await ref.read(locationProvider.notifier).startLocationStream(
        driverId: driverId,
        deviceId: 'android-${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('🟢 Restored shift active with duty ON (tracking resumed)');
    } else {
      debugPrint(
        '⚪ Restored state (checkedIn=$checkedIn, dutyOn=$effectiveDutyOn)',
      );
    }
  }

  Future<void> _performAttendance() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final uiNotifier = ref.read(attendanceUiProvider.notifier);
    final auth = ref.read(authNotifierProvider);
    final api = ref.read(apiServiceProvider);
    final mobile = auth.mobile ?? '';

    // ✅ STEP 1: Check permission status first
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // 🔔 Show prominent disclosure BEFORE system permission dialog (Play requirement)
      final prefs = await SharedPreferences.getInstance();
      final hasSeenDisclosure =
          prefs.getBool('location_disclosure_shown') ?? false;

      if (!hasSeenDisclosure) {
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Location tracking in the background'),
            content: const SingleChildScrollView(
              child: Text(
                'This app collects your location even when the app is in the '
                    'background or the screen is off, but only while you are '
                    'checked in for duty.\n\n'
                    'Your location is used so the transport/operations team can '
                    'see your live position, verify routes and stops, and generate '
                    'trip and attendance reports. Your data is sent securely to '
                    'your company and is not used for advertising.\n\n'
                    'You can stop tracking at any time by checking out / logging '
                    'out or by turning off location permission in system settings.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('I agree'),
              ),
            ],
          ),
        ) ??
            false;

        if (!accepted) {
          // User did NOT consent → stop here
          setState(() => _isLoading = false);
          return;
        }

        await prefs.setBool('location_disclosure_shown', true);
      }

      // 👉 Only AFTER user has seen & accepted disclosure, show system permission dialog
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      // ❗ Permission denied again — show dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
              'Location access is required to check in. Please enable location permission in settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      // 🚫 Permanently denied — direct to app settings
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Permanently Denied'),
          content: const Text(
              'You have permanently denied location permission. Please enable it manually from settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    // ✅ STEP 2: Get current position safely
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings:
        const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      _showToast('Location error: $e', isError: true);
      setState(() => _isLoading = false);
      return;
    }

    // ✅ STEP 3: Perform check-in API call
    try {
      final response = await api.driverAttendance(
        mobile: mobile,
        lat: pos.latitude,
        long: pos.longitude,
      );

      final data = response.data;
      final message = data['message'] ?? 'Check-in successful';
      _showToast(message);

      uiNotifier.forceCheckedIn(true);
      await _saveAttendanceToPrefs(true);

      // 🔹 NEW: when check-in success, duty auto ON
      ref.read(dutyToggleProvider.notifier).state = true;
      await _saveDutyToPrefs(true);

      await ref.read(locationProvider.notifier).startLocationStream(
        driverId: mobile,
        deviceId: 'android-${DateTime.now().millisecondsSinceEpoch}',
      );

      await uiNotifier.startCountdown(10);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      final action = (data is Map ? (data['action'] ?? '') : '').toString();
      final msg = (data is Map ? (data['message'] ?? '') : '').toString();

      if (code == 409 && action == 'stop_already_logged') {
        _showToast(msg.isNotEmpty ? msg : 'Already checked in');
        uiNotifier.forceCheckedIn(true);
        await _saveAttendanceToPrefs(true);

        // 🔹 NEW: already logged in → duty ON as well
        ref.read(dutyToggleProvider.notifier).state = true;
        await _saveDutyToPrefs(true);

        await ref.read(locationProvider.notifier).startLocationStream(
          driverId: mobile,
          deviceId: 'android-${DateTime.now().millisecondsSinceEpoch}',
        );
      } else {
        _showToast(msg.isNotEmpty ? msg : 'Error occurred', isError: true);
      }
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Logout logic
  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await ref.read(authNotifierProvider.notifier).logout();
      await ref.read(locationProvider.notifier).stopLocationStream();

      // 🧹 Clear attendance data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('checked_in');
      await prefs.remove('last_toggled_at');
      await prefs.remove('isCheckedIn'); // 🔹 NEW
      await prefs.remove('isDutyOn');    // 🔹 NEW

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(attendanceUiProvider);
    final auth = ref.watch(authNotifierProvider);
    final pos = ref.watch(locationProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final dutyOn = ref.watch(dutyToggleProvider); // 🔹 NEW

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      appBar: AppBar(
        backgroundColor: TWCColors.coffeeDark,
        centerTitle: true,
        title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await _confirmAndLogout(context, ref);
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 18),
              _buildAvatar(auth.mobile ?? ''),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: _buildCheckInButton(ui),
                      ),
                      const SizedBox(height: 32),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey<bool>(ui.checkedIn),
                          children: [
                            Text(
                              ui.checkedIn
                                  ? 'Shift is Active'
                                  : 'You Are Off Duty',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            // 🔹 NEW: Rapido-style duty toggle, only when checked in
                            if (ui.checkedIn) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    dutyOn ? 'On Duty' : 'Off Duty',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: dutyOn,
                                    onChanged: (value) async {
                                      final auth =
                                      ref.read(authNotifierProvider);
                                      final driverId =
                                          auth.mobile ?? 'unknown';

                                      ref
                                          .read(
                                          dutyToggleProvider.notifier)
                                          .state = value;
                                      await _saveDutyToPrefs(value);

                                      if (value) {
                                        // turned ON → start tracking (only if still checked in)
                                        if (ref
                                            .read(attendanceUiProvider)
                                            .checkedIn) {
                                          await ref
                                              .read(locationProvider.notifier)
                                              .startLocationStream(
                                            driverId: driverId,
                                            deviceId:
                                            'android-${DateTime.now().millisecondsSinceEpoch}',
                                          );
                                          debugPrint(
                                              '🟢 Duty switch ON – tracking started');
                                        }
                                      } else {
                                        // turned OFF → stop tracking
                                        await ref
                                            .read(locationProvider.notifier)
                                            .stopLocationStream();
                                        debugPrint(
                                            '⭕ Duty switch OFF – tracking stopped');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 6),
                            Text(
                              'Last: ${DateFormat('hh:mm:ss a, dd MMM yyyy').format(DateTime.now())}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                            if (pos != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Location: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _buildSyncBadge(syncStatus),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text(
                  'Press the button to Check-In',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String mobile) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const CircleAvatar(radius: 24, child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome,', style: TextStyle(fontSize: 14)),
              Text(
                mobile,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInButton(AttendanceUiState ui) {
    final notifier = ref.read(attendanceUiProvider.notifier);

    final outsetDecoration = BoxDecoration(
      color: TWCColors.coffeeDark,
      borderRadius: BorderRadius.circular(30),
      boxShadow: ui.isPressed
          ? []
          : [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          offset: const Offset(6, 6),
          blurRadius: 12,
        ),
        BoxShadow(
            color: Colors.white.withValues(alpha: 0.2),
            offset: const Offset(-6, -6),
            blurRadius: 12),
      ],
    );

    final insetDecoration = BoxDecoration(
      color: TWCColors.latteBg,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          offset: const Offset(-4, -4),
          blurRadius: 8,
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.8),
          offset: const Offset(4, 4),
          blurRadius: 8,
        ),
      ],
    );

    if (_isLoading || ui.countdown > 0) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: insetDecoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: TWCColors.coffeeDark,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              ui.countdown > 0
                  ? 'Please wait (${ui.countdown}s)...'
                  : 'Checking in...',
              style: const TextStyle(
                fontSize: 18,
                color: TWCColors.coffeeDark,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTapDown: (_) => Future.microtask(() {
        if (mounted) notifier.setPressed(true);
      }),
      onTapUp: (_) async {
        Future.microtask(() {
          if (mounted) notifier.setPressed(false);
        });
        await _performAttendance();
      },
      onTapCancel: () => Future.microtask(() {
        if (mounted) notifier.setPressed(false);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        transform: ui.isPressed
            ? Matrix4.translationValues(2, 2, 0)
            : Matrix4.identity(),
        decoration: outsetDecoration,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            SizedBox(width: 12),
            Text(
              'Check In',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncBadge(SyncStatus status) {
    switch (status) {
      case SyncStatus.syncing:
        return const Text(
          '⏳ Syncing...',
          style: TextStyle(color: Colors.orange, fontSize: 13),
        );
      case SyncStatus.offline:
        return const Text(
          '⚠️ Offline — saving locally',
          style: TextStyle(color: Colors.redAccent, fontSize: 13),
        );
      case SyncStatus.idle:
        return const Text(
          '✅ All data synced',
          style: TextStyle(color: Colors.green, fontSize: 13),
        );
    }
  }
}