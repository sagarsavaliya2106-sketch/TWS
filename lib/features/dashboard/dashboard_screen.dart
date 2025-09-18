// lib/features/dashboard/dashboard_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/features/auth/login_screen.dart';
import 'package:untitled/widgets/twc_toast.dart';

import '../../theme/colors.dart';
import '../../service/providers/api_and_auth.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

// lib/features/dashboard/dashboard_screen.dart

class _DashboardScreenState extends ConsumerState<DashboardScreen> with TickerProviderStateMixin {
  bool _checkedIn = false;
  DateTime? _lastToggledAt;

  // New state for handling the 3D press animation
  bool _isPressed = false;

  // animation controllers
  late final AnimationController _pulseController;

  // loading state for API call
  bool _isLoading = false;

  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

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

  // --- All your existing methods for SharedPreferences, Toast, API calls, and Logout Dialog remain the same ---
  // ... ( _restoreAttendanceFromPrefs, _saveAttendanceToPrefs, _clearAttendanceFromPrefs )
  // ... ( _removeToast, _performAttendance, _confirmAndLogout, _buildAvatar )

  // PASTE ALL YOUR OTHER METHODS HERE, from _restoreAttendanceFromPrefs down to _buildAvatar.
  // The provided code below only contains the NEW button widget and the updated `build` method.
  // For your convenience, I am including them all again here.

  // -------------------------
  // SharedPreferences persistence
  // -------------------------
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
        }
      }
    } catch (e) {
      // ignore restore errors
    }
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
    } catch (e) {
      // ignoring save errors
    }
  }

  Future<void> _clearAttendanceFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kCheckedInKey);
      await sp.remove(_kLastToggledAtKey);
    } catch (e) {
      // ignoring clear errors
    }
  }

  // -------------------------
  // Toast implementation
  // -------------------------
  void _removeToast() {
    try {
      _toastEntry?.remove();
    } catch (_) {}
    _toastEntry = null;
  }

  // -------------------------
  // API call & loading state
  // -------------------------
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
          if (!mounted) return;
          _pulseController.forward(from: 0.0);
          showTwcToast(context, serverMessage ?? (_checkedIn ? 'Checked in' : 'Checked out'), isError: false);
        } else {
          final message = serverMessage ?? 'Server returned an error during attendance.';
          showTwcToast(context, message, isError: true);
        }
      } else {
        showTwcToast(context, 'Unexpected server response', isError: true);
      }
    } on DioException catch (e) {
      String message = 'Network error. Please check your connection.';
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
        message = 'Request timed out. Please try again.';
      } else if (e.type == DioExceptionType.unknown) {
        message = 'Cannot reach the server. Please check your internet or VPN.';
      } else if (e.response != null) {
        final d = e.response!.data;
        if (d is Map && d['message'] != null) {
          message = d['message'].toString();
        }
      }
      if (!mounted) return;
      showTwcToast(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      showTwcToast(context, 'Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // -------------------------
  // Logout Dialog
  // -------------------------
  Future<void> _confirmAndLogout() async {
    // ... This method remains exactly the same as in your original code
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 8)), ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration( color: const Color.fromRGBO(45, 60, 75, 0.06), borderRadius: BorderRadius.circular(12), ),
                      child: Icon(Icons.logout, color: TWCColors.coffeeDark, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Confirm logout', style: const TextStyle( fontFamily: 'Lato', fontSize: 20, fontWeight: FontWeight.w700, color: TWCColors.coffeeDark, ), ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text( 'Are you sure you want to logout?', style: const TextStyle( fontFamily: 'Merriweather', fontSize: 15, color: Colors.black87, ), ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom( side: BorderSide(color: TWCColors.coffeeDark.withOpacity(0.14)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12), foregroundColor: TWCColors.coffeeDark, backgroundColor: Colors.white, ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel', style: TextStyle(fontFamily: 'Lato', fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom( backgroundColor: TWCColors.accentBurgundy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12), elevation: 2, ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Logout', style: TextStyle(fontFamily: 'Lato', fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLogout == true) {
      await ref.read(authNotifierProvider.notifier).logout();
      await _clearAttendanceFromPrefs();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  // -------------------------
  // Avatar Widget
  // -------------------------
  Widget _buildAvatar(String mobile) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: TWCColors.coffeeDark.withOpacity(0.08),
          child: const Icon(Icons.admin_panel_settings, color: TWCColors.coffeeDark),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome,', style: TextStyle(fontFamily: 'Merriweather', fontSize: 14, color: Color(0xFF2D3C4B))),
            const SizedBox(height: 2),
            Text(mobile, style: const TextStyle(fontFamily: 'Merriweather', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3C4B))),
          ],
        ),
      ],
    );
  }

  // --- NEW 3D BUTTON WIDGET ---
  Widget _buildThreeDeeButton() {
    // Styling for the "Outset" button (when checked out)
    final outsetDecoration = BoxDecoration(
      color: TWCColors.coffeeDark,
      borderRadius: BorderRadius.circular(30),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          TWCColors.coffeeDark.withRed(80), // Lighter shade for top-left highlight
          TWCColors.coffeeDark,
        ],
      ),
      boxShadow: _isPressed ? [] : [
        // Bottom-right dark shadow for raised effect
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          offset: const Offset(6, 6),
          blurRadius: 12,
        ),
        // Top-left light shadow for raised effect
        BoxShadow(
          color: TWCColors.coffeeDark.withOpacity(0.8).withRed(90),
          offset: const Offset(-6, -6),
          blurRadius: 12,
        ),
      ],
    );

    // Styling for the "Inset" button (when checked in)
    final insetDecoration = BoxDecoration(
      color: TWCColors.latteBg,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        // Top-left dark shadow for pressed-in effect
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          offset: const Offset(-4, -4),
          blurRadius: 8,
        ),
        // Bottom-right light shadow for pressed-in effect
        BoxShadow(
          color: Colors.white.withOpacity(0.9),
          offset: const Offset(4, 4),
          blurRadius: 8,
        ),
      ],
    );

    // Determine current state
    bool isCheckedIn = _checkedIn;
    final decoration = isCheckedIn ? insetDecoration : outsetDecoration;
    final icon = isCheckedIn ? Icons.stop_rounded : Icons.play_arrow_rounded;
    final label = isCheckedIn ? 'End Shift' : 'Start Shift';
    final textColor = isCheckedIn ? TWCColors.coffeeDark : Colors.white;

    // --- Loading State ---
    if (_isLoading) {
      return Container(
          height: 80,
          alignment: Alignment.center,
          decoration: insetDecoration,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: TWCColors.coffeeDark),
              ),
              SizedBox(width: 16),
              Text('Please wait...', style: TextStyle(fontFamily: 'Lato', fontSize: 18, color: TWCColors.coffeeDark)),
            ],
          ));
    }

    // --- Interactive Button ---
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _performAttendance(); // Trigger API call
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 80,
        // Apply a slight downward shift when pressed
        transform: _isPressed ? Matrix4.translationValues(2, 2, 0) : Matrix4.identity(),
        decoration: decoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 30),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final mobile = auth.mobile ?? 'Unknown';

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      appBar: AppBar(
        backgroundColor: TWCColors.coffeeDark,
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Dashboard', style: TextStyle(fontFamily: 'Lato', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmAndLogout,
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
              Align(
                alignment: Alignment.centerLeft,
                child: _buildAvatar(mobile),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Our new 3D button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: _buildThreeDeeButton(),
                      ),

                      const SizedBox(height: 32),

                      // Status + last toggled (animated)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                        child: Column(
                          key: ValueKey<bool>(_checkedIn),
                          children: [
                            Text(
                              _checkedIn ? 'Shift is Active' : 'You Are Off Duty',
                              style: const TextStyle(fontFamily: 'Merriweather', fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF2D3C4B)),
                            ),
                            if (_lastToggledAt != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Last: ${DateFormat('hh:mm:ss a, dd MMM yyyy').format(_lastToggledAt!)}',
                                style: const TextStyle(fontFamily: 'Merriweather', fontSize: 13, color: Colors.black54),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: const Text(
                  'Press the button to start or end your shift',
                  style: TextStyle(fontFamily: 'Merriweather', fontSize: 13, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
