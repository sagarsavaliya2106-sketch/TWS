import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:untitled/features/dashboard/dashboard_screen.dart';
import 'package:untitled/widgets/twc_toast.dart';

import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../widgets/twc_logo_header.dart';
import '../../widgets/twc_primary_button.dart';
import '../../service/providers/api_and_auth.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String mobile;
  const OtpScreen({super.key, required this.mobile});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentOtp => _controllers.map((c) => c.text).join();

  void _onDigitChanged(String value, int index) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length > 1) {
      final digits = cleaned.split('');
      var pos = index;
      for (var d in digits) {
        if (pos < 4) {
          _controllers[pos].text = d;
          pos++;
        }
      }
      final next = pos < 4 ? pos : 3;
      _focusNodes[next].requestFocus();
      setState(() {});
      return;
    }

    if (value.isNotEmpty) {
      if (index < 3) _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  Future<void> _onVerify() async {
    if (mounted) setState(() => _errorText = null);

    final otp = _currentOtp;
    if (otp.length != 4 || otp.contains(RegExp(r'\D'))) {
      if (mounted) setState(() => _errorText = 'Please enter the 4-digit OTP');
      return;
    }

    if (otp != '1234') {
      if (mounted) setState(() => _errorText = 'Invalid OTP. Use 1234 for demo.');
      return;
    }

    if (mounted) setState(() => _loading = true);

    try {
      // ✅ Save mobile locally first
      await ref.read(authNotifierProvider.notifier).setMobileOnly(widget.mobile);

      // ✅ Verify mobile with server
      final result = await ref.read(authNotifierProvider.notifier).verifyMobileOnServer();

      if (!mounted) return;

      if (result['ok'] == true) {
        // ✅ Pass employee info from API to AuthNotifier
        await ref.read(authNotifierProvider.notifier).completeLogin(
          employeeId: result['employeeId'],
          employeeName: result['employeeName'],
        );

        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (route) => false,
        );
      } else {
        final msg = result['message']?.toString() ?? 'Server verification failed';
        final lower = msg.toLowerCase();
        final isNetworkLike = lower.contains('failed host lookup') ||
            lower.contains('socketexception') ||
            lower.contains('network error') ||
            lower.contains('timed out') ||
            lower.contains('cannot reach') ||
            lower.contains('dns') ||
            lower.contains('host lookup');

        if (isNetworkLike) {
          showTwcToast(context, 'Network error — please check connection', isError: true);
        } else {
          if (mounted) setState(() => _errorText = msg);
        }
      }
    } on DioException catch (e) {
      String message = 'Network error. Please check your connection.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        message = 'Request timed out. Please try again.';
      } else if (e.type == DioExceptionType.unknown) {
        message = 'Cannot reach the server. Please check your internet or VPN.';
      } else if (e.response != null) {
        final d = e.response!.data;
        if (d is Map && d['message'] != null) message = d['message'].toString();
      }
      if (!mounted) return;
      showTwcToast(context, message, isError: true);
    } catch (e) {
      if (!mounted) return;
      final msg = 'Error: ${e.toString()}';
      if (mounted) setState(() => _errorText = msg);
      showTwcToast(context, msg, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 58,
      height: 58,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              if (_controllers[index].text.isEmpty && index > 0) {
                _focusNodes[index - 1].requestFocus();
                _controllers[index - 1].clear();
                setState(() {});
              }
            }
          }
        },
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(
            fontFamily: 'Lato',   // ✅ use your local font
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: TWCColors.coffeeDark,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => _onDigitChanged(v, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phoneShown = widget.mobile.length > 4 ? '•••• ${widget.mobile.substring(widget.mobile.length - 4)}' : widget.mobile;

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const TWCLogoHeader(size: 84),
                const SizedBox(height: 18),
                Text('Verify OTP', style: TWCTextStyles.heading),
                const SizedBox(height: 8),
                Text('Enter the 4-digit code sent to +91 $phoneShown', style: TWCTextStyles.subtitle, textAlign: TextAlign.center),
                const SizedBox(height: 20),

                // OTP boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (i) => _buildOtpBox(i)),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],

                const SizedBox(height: 18),

                // Verify button (calls server after local OTP check)
                TWCPrimaryButton(label: 'Verify', onPressed: _onVerify, loading: _loading),

                const SizedBox(height: 30),
                // Footer intentionally removed per request
              ],
            ),
          ),
        ),
      ),
    );
  }
}
