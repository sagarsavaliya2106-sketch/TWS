import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // animation controllers (created in initState)
  late final AnimationController _pressController;
  late final AnimationController _pulseController;

  // loading state for API call
  bool _isLoading = false;

  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _pulseController.reverse();
    });

    // restore persisted attendance state (non-blocking)
    _restoreAttendanceFromPrefs();
  }

  @override
  void dispose() {
    _pressController.dispose();
    _pulseController.dispose();
    _removeToast();
    super.dispose();
  }

  // -------------------------
  // SharedPreferences persistence (Option A)
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
      // ignore restore errors (don't block UI)
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
      // ignoring save errors (optional: show a toast)
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

  void _showToast(String message, {bool isError = false, Duration duration = const Duration(seconds: 3)}) {
    // remove existing
    _removeToast();

    final overlay = Overlay.of(context);

    final themeBg = isError ? Colors.red.shade600 : Colors.green.shade600;
    final textColor = Colors.white;

    _toastEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 36,
          left: 24,
          right: 24,
          child: Material(
            color: Colors.transparent,
            child: AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: themeBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: textColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: GoogleFonts.lato(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_toastEntry!);

    // auto remove
    Timer(duration, () {
      _removeToast();
    });
  }

  // -------------------------
  // API call & loading state
  // -------------------------
  Future<void> _performAttendance() async {
    final mobile = ref.read(authNotifierProvider).mobile;
    if (mobile == null || mobile.isEmpty) {
      _showToast('Mobile not found. Please login again.', isError: true);
      return;
    }

    if (_isLoading) return; // prevent double-tap

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      final resp = await api.driverAttendance(mobile);

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final status = data['status']?.toString().toLowerCase();
        final serverMessage = data['message']?.toString();

        if (status == 'success') {
          setState(() {
            _checkedIn = !_checkedIn;
            _lastToggledAt = DateTime.now();
          });

          // persist locally
          await _saveAttendanceToPrefs();

          // pulse animation
          _pulseController.forward(from: 0.0);

          _showToast(serverMessage ?? (_checkedIn ? 'Checked in' : 'Checked out'), isError: false);
        } else {
          final message = serverMessage ?? 'Server returned an error during attendance.';
          _showToast(message, isError: true);
        }
      } else {
        _showToast('Unexpected server response', isError: true);
      }
    } on DioException catch (e) {
      String message = 'Network error';
      if (e.response != null) {
        final d = e.response!.data;
        if (d is Map && d['message'] != null) message = d['message'].toString();
      } else if (e.message != null) {
        message = e.message!;
      }
      _showToast('Error: $message', isError: true);
    } catch (e) {
      _showToast('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Show confirmation dialog and logout if user confirms.
  Future<void> _confirmAndLogout() async {
    final navigator = Navigator.of(context);

    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 8)),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon + title row
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(45, 60, 75, 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.logout, color: TWCColors.coffeeDark, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Confirm logout',
                        style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.w700, color: TWCColors.coffeeDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Are you sure you want to logout?',
                    style: GoogleFonts.merriweather(fontSize: 15, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: TWCColors.coffeeDark.withValues(alpha: 0.14)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: TWCColors.coffeeDark,
                          backgroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text('Cancel', style: GoogleFonts.lato(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TWCColors.accentBurgundy,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 2,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text('Logout', style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: Colors.white)),
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

      // clear persisted attendance
      await _clearAttendanceFromPrefs();

      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Widget _buildAvatar(String mobile) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: TWCColors.coffeeDark.withValues(alpha: 0.08),
          child: const Icon(Icons.admin_panel_settings, color: TWCColors.coffeeDark),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome,', style: GoogleFonts.merriweather(fontSize: 14, color: TWCColors.coffeeDark.withValues(alpha: 0.8))),
            const SizedBox(height: 2),
            Text(mobile, style: GoogleFonts.merriweather(fontSize: 18, color: TWCColors.coffeeDark, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(double size) {
    final primary = _checkedIn ? Colors.deepOrange.shade600 : Colors.green.shade600;
    final icon = _checkedIn ? Icons.check_circle_outline : Icons.login;
    final label = _checkedIn ? 'Check-Out' : 'Check-In';

    final pulse = Tween<double>(begin: 0.0, end: 18.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    // When loading: show a disabled circular button with a small spinner + label
    if (_isLoading) {
      return Transform.scale(
        scale: _pressController.value,
        child: Material(
          color: primary.withValues(alpha: 0.9),
          shape: const CircleBorder(),
          elevation: 6,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size * 0.14,
                  height: size * 0.14,
                  child: const CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                ),
                const SizedBox(height: 10),
                Text(
                  'Please wait',
                  style: GoogleFonts.lato(
                    fontSize: size * 0.09,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal interactive button
    return AnimatedBuilder(
      animation: Listenable.merge([_pressController, _pulseController]),
      builder: (context, _) {
        final scale = _pressController.value;
        final glowSpread = pulse.value;
        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // animated glow
              Container(
                width: size + glowSpread,
                height: size + glowSpread,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.22),
                      blurRadius: 24 + glowSpread / 2,
                      spreadRadius: glowSpread / 6,
                    ),
                  ],
                ),
              ),

              // main circular button with ripple
              Material(
                color: primary,
                shape: const CircleBorder(),
                elevation: 6,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _performAttendance,
                  onTapDown: (_) => _pressController.reverse(),
                  onTapCancel: () => _pressController.forward(),
                  onTapUp: (_) => _pressController.forward(),
                  splashColor: Colors.white24,
                  child: Container(
                    width: size,
                    height: size,
                    padding: EdgeInsets.symmetric(vertical: size * 0.12),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: size * 0.24, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: GoogleFonts.lato(
                            fontSize: size * 0.11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final mobile = auth.mobile ?? 'Unknown';

    final width = MediaQuery.of(context).size.width;
    final buttonSize = (width * 0.45).clamp(140.0, 260.0);

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      appBar: AppBar(
        backgroundColor: TWCColors.coffeeDark,
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text('Dashboard', style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
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

              // Welcome row with avatar + phone
              Align(
                alignment: Alignment.centerLeft,
                child: _buildAvatar(mobile),
              ),

              // center content
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // action button
                      _buildActionButton(buttonSize),

                      const SizedBox(height: 22),

                      // status + last toggled (animated)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                        child: Column(
                          key: ValueKey<bool>(_checkedIn),
                          children: [
                            Text(
                              _checkedIn ? 'You are checked in' : 'You are checked out',
                              style: GoogleFonts.merriweather(fontSize: 18, color: TWCColors.coffeeDark, fontWeight: FontWeight.w600),
                            ),
                            if (_lastToggledAt != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Last: ${DateFormat('hh:mm:ss a, dd MMM yyyy').format(_lastToggledAt!)}',
                                style: GoogleFonts.merriweather(fontSize: 13, color: Colors.black54),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // footer hint (closer to action)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  'Tap the button to toggle Check-In / Check-Out',
                  style: GoogleFonts.merriweather(fontSize: 13, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
