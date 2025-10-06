import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/features/auth/login_screen.dart';
import 'package:untitled/features/location/location_provider.dart';
import 'package:untitled/widgets/twc_toast.dart';
import '../../theme/colors.dart';
import '../../service/providers/api_and_auth.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with TickerProviderStateMixin {
  bool _checkedIn = false;
  DateTime? _lastToggledAt;
  bool _isPressed = false;
  late final AnimationController _pulseController;
  bool _isLoading = false;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600), lowerBound: 0.0, upperBound: 1.0);
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _pulseController.reverse();
    });
    _restoreAttendanceFromPrefs();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _removeToast();
    super.dispose();
  }

  static const _kCheckedInKey = 'checked_in';
  static const _kLastToggledAtKey = 'last_toggled_at';

  Future<void> _restoreAttendanceFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final savedChecked = sp.getBool(_kCheckedInKey);
      final savedIso = sp.getString(_kLastToggledAtKey);
      if (savedChecked != null) {
        DateTime? dt;
        if (savedIso != null && savedIso.isNotEmpty) {
          try {
            dt = DateTime.parse(savedIso);
          } catch (_) {
            dt = null;
          }
        }
        if (mounted) {
          setState(() {
            _checkedIn = savedChecked;
            _lastToggledAt = dt;
          });
          // auto resume tracking if still checked in
          if (_checkedIn) {
            final authState = ref.read(authNotifierProvider);
            final employeeId = authState.employeeId ?? 'unknown';
            final deviceId = "DEVICE-${DateTime.now().millisecondsSinceEpoch}";

            await ref.read(locationProvider.notifier).startLocationStream(
              employeeId: employeeId,
              deviceId: deviceId,
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveAttendanceToPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kCheckedInKey, _checkedIn);
      if (_lastToggledAt != null) {
        await sp.setString(_kLastToggledAtKey, _lastToggledAt!.toIso8601String());
      } else {
        await sp.remove(_kLastToggledAtKey);
      }
    } catch (_) {}
  }

  Future<void> _clearAttendanceFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kCheckedInKey);
      await sp.remove(_kLastToggledAtKey);
    } catch (_) {}
  }

  void _removeToast() {
    try {
      _toastEntry?.remove();
    } catch (_) {}
    _toastEntry = null;
  }

  Future<void> _performAttendance() async {
    final mobile = ref.read(authNotifierProvider).mobile;
    if (mobile == null || mobile.isEmpty) {
      showTwcToast(context, 'Mobile not found. Please login again.', isError: true);
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      final resp = await api.driverAttendance(mobile);
      if (!mounted) return;

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final status = data['status']?.toString().toLowerCase();
        final serverMessage = data['message']?.toString();

        if (status == 'success') {
          setState(() {
            _checkedIn = !_checkedIn;
            _lastToggledAt = DateTime.now();
          });
          await _saveAttendanceToPrefs();

          // ✅ Prepare IDs for location provider
          final authState = ref.read(authNotifierProvider);
          final employeeId = authState.employeeId ?? 'unknown';
          final deviceId = "DEVICE-${DateTime.now().millisecondsSinceEpoch}";

          if (_checkedIn) {
            // ✅ Start location tracking
            try {
              await ref.read(locationProvider.notifier).fetchCurrentLocation(
                employeeId: employeeId,
                deviceId: deviceId,
              );

              await ref.read(locationProvider.notifier).startLocationStream(
                employeeId: employeeId,
                deviceId: deviceId,
              );

              final loc = ref.read(locationProvider);
              debugPrint("📡 Location stored in state: ${loc?.toJson()}");
            } catch (e) {
              if (!mounted) return;
              debugPrint("⚠️ Location error: $e");
              showTwcToast(context, 'Location permission required for shift tracking.', isError: true);
            }
          } else {
            // ✅ Stop tracking when shift ends
            await ref.read(locationProvider.notifier).stopLocationStream();
            ref.read(locationProvider.notifier).clearLocation();
            debugPrint("🔴 Shift ended, location tracking stopped.");
          }

          _pulseController.forward(from: 0.0);
          if (!mounted) return;
          showTwcToast(
            context,
            serverMessage ?? (_checkedIn ? 'Checked in' : 'Checked out'),
            isError: false,
          );
        } else {
          if (!mounted) return;
          final message = serverMessage ?? 'Server returned an error.';
          showTwcToast(context, message, isError: true);
        }
      } else {
        if (!mounted) return;
        showTwcToast(context, 'Unexpected server response.', isError: true);
      }
    } on DioException catch (e) {
      String message = 'Network error.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        message = 'Request timed out. Please try again.';
      } else if (e.response?.data is Map && e.response?.data['message'] != null) {
        message = e.response!.data['message'].toString();
      }
      if (!mounted) return;
      showTwcToast(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTwcToast(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirm logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Logout')),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await ref.read(authNotifierProvider.notifier).logout();
      await ref.read(locationProvider.notifier).stopLocationStream();
      await _clearAttendanceFromPrefs();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    }
  }

  Widget _buildAvatar(String mobile) {
    return Row(
      children: [
        const CircleAvatar(radius: 24, child: Icon(Icons.person)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome,', style: TextStyle(fontSize: 14)),
            Text(mobile, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ],
    );
  }

  Widget _buildThreeDeeButton() {
    final outsetDecoration = BoxDecoration(
      color: TWCColors.coffeeDark,
      borderRadius: BorderRadius.circular(30),
      boxShadow: _isPressed
          ? []
          : [
        BoxShadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(6, 6), blurRadius: 12),
        BoxShadow(color: Colors.white.withValues(alpha: 0.2), offset: const Offset(-6, -6), blurRadius: 12),
      ],
    );

    final insetDecoration = BoxDecoration(
      color: TWCColors.latteBg,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.2), offset: const Offset(-4, -4), blurRadius: 8),
        BoxShadow(color: Colors.white.withValues(alpha: 0.8), offset: const Offset(4, 4), blurRadius: 8),
      ],
    );

    final isCheckedIn = _checkedIn;
    final decoration = isCheckedIn ? insetDecoration : outsetDecoration;
    final icon = isCheckedIn ? Icons.stop_rounded : Icons.play_arrow_rounded;
    final label = isCheckedIn ? 'End Shift' : 'Start Shift';
    final textColor = isCheckedIn ? TWCColors.coffeeDark : Colors.white;

    if (_isLoading) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: insetDecoration,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: TWCColors.coffeeDark)),
            SizedBox(width: 16),
            Text('Please wait...', style: TextStyle(fontSize: 18, color: TWCColors.coffeeDark)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _performAttendance();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        transform: _isPressed ? Matrix4.translationValues(2, 2, 0) : Matrix4.identity(),
        decoration: decoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 30),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final mobile = auth.mobile ?? 'Unknown';
    final pos = ref.watch(locationProvider);

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      appBar: AppBar(
        backgroundColor: TWCColors.coffeeDark,
        centerTitle: true,
        title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
        actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _confirmAndLogout)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft, child: _buildAvatar(mobile)),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 20.0), child: _buildThreeDeeButton()),
                      const SizedBox(height: 32),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey<bool>(_checkedIn),
                          children: [
                            Text(
                              _checkedIn ? 'Shift is Active' : 'You Are Off Duty',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            if (_lastToggledAt != null) ...[
                              const SizedBox(height: 6),
                              Text('Last: ${DateFormat('hh:mm:ss a, dd MMM yyyy').format(_lastToggledAt!)}',
                                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
                            ],
                            if (pos != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Location: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(fontSize: 13, color: Colors.black54),
                              ),
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
                child: Text('Press the button to start or end your shift', style: TextStyle(fontSize: 13, color: Colors.black54)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
