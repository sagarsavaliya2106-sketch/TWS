import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:untitled/features/dashboard/dashboard_screen.dart';

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
    setState(() {
      _errorText = null;
    });

    final otp = _currentOtp;
    if (otp.length != 4 || otp.contains(RegExp(r'\D'))) {
      setState(() {
        _errorText = 'Please enter the 4-digit OTP';
      });
      return;
    }

    // local OTP check (demo)
    if (otp != '1234') {
      setState(() {
        _errorText = 'Invalid OTP. Use 1234 for demo.';
      });
      return;
    }

    // OTP ok locally — now call the server to verify mobile registration
    setState(() => _loading = true);

    // Ensure mobile saved in auth state
    await ref.read(authNotifierProvider.notifier).setMobileOnly(widget.mobile);

    final result = await ref.read(authNotifierProvider.notifier).verifyMobileOnServer();

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['ok'] == true) {
      await ref.read(authNotifierProvider.notifier).completeLogin();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (route) => false,
        );
      }

    } else {
      final msg = result['message']?.toString() ?? 'Server verification failed';
      setState(() => _errorText = msg);

      // ❌ REMOVE auto pop back to login
      // User stays on OTP screen until they choose to go back.
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 58,
      height: 58,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (KeyEvent event) {
          // We only care about key-down events for backspace handling
          if (event is KeyDownEvent) {
            // LogicalKeyboardKey.backspace is the backspace key
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              // If current is empty, move focus back and clear previous
              if (_controllers[index].text.isEmpty && index > 0) {
                _focusNodes[index - 1].requestFocus();
                _controllers[index - 1].clear();
                setState(() {}); // update UI
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
          style: GoogleFonts.lato(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: TWCColors.coffeeDark,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
