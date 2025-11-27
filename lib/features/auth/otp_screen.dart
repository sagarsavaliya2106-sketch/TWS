import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:untitled/features/dashboard/dashboard_screen.dart';
import 'package:untitled/widgets/twc_toast.dart';

import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../widgets/twc_logo_header.dart';
import '../../widgets/twc_primary_button.dart';
import '../../service/providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String mobile;
  const OtpScreen({super.key, required this.mobile});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers =
  List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  bool _loading = false;
  bool _canResend = false;
  int _secondsRemaining = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Autofocus first box
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  String get _currentOtp => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete =>
      _currentOtp.length == 4 && !_currentOtp.contains(RegExp(r'\D'));

  void _onDigitChanged(String value, int index) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), '');

    // Handle paste
    if (cleaned.length > 1) {
      final digits = cleaned.split('');
      var pos = index;
      for (var d in digits) {
        if (pos < _controllers.length) {
          _controllers[pos].text = d;
          pos++;
        }
      }
      final next = pos < _controllers.length ? pos : _controllers.length - 1;
      _focusNodes[next].requestFocus();
      setState(() {});
      return;
    }

    // Handle single entry
    if (value.isNotEmpty) {
      if (index < _controllers.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    setState(() {});
  }

  Future<void> _onVerify() async {
    if (!_isOtpComplete) {
      showTwcToast(context, 'Please enter the 4-digit OTP', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final result =
      await ref.read(authNotifierProvider.notifier).verifyOtp(widget.mobile, _currentOtp);

      if (result['ok'] == true) {
        await ref.read(authNotifierProvider.notifier).completeLogin(mobile: widget.mobile);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (route) => false,
        );
      } else {
        showTwcToast(context, result['message'] ?? 'Invalid or expired OTP', isError: true);
      }
    } catch (e) {
      showTwcToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onResendOtp() async {
    if (!_canResend) return;
    try {
      showTwcToast(context, 'Sending new OTP...');
      final result = await ref.read(authNotifierProvider.notifier).sendOtp(widget.mobile);
      if (result['ok'] == true) {
        showTwcToast(context, 'OTP resent successfully');
        for (var c in _controllers) c.clear();
        _focusNodes.first.requestFocus();
        _startTimer();
      } else {
        showTwcToast(context, result['message'] ?? 'Failed to resend OTP', isError: true);
      }
    } catch (e) {
      showTwcToast(context, e.toString(), isError: true);
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 55,
      height: 60,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _controllers[index].text.isEmpty &&
              index > 0) {
            _focusNodes[index - 1].requestFocus();
            _controllers[index - 1].clear();
            setState(() {});
          }
        },
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: TWCColors.coffeeDark,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: TWCColors.coffeeDark.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: TWCColors.coffeeDark, width: 1.8),
            ),
          ),
          onChanged: (v) => _onDigitChanged(v, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phoneShown = widget.mobile.length > 4
        ? '•••• ${widget.mobile.substring(widget.mobile.length - 4)}'
        : widget.mobile;

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TWCLogoHeader(size: 84),
                const SizedBox(height: 18),
                Text('Verify OTP', style: TWCTextStyles.heading),
                const SizedBox(height: 8),
                Text('Enter the 4-digit code sent to +91 $phoneShown',
                    style: TWCTextStyles.subtitle,
                    textAlign: TextAlign.center),
                const SizedBox(height: 26),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (i) => _buildOtpBox(i)),
                ),

                const SizedBox(height: 30),
                TWCPrimaryButton(
                  label: 'Verify',
                  onPressed: _isOtpComplete && !_loading ? _onVerify : null,
                  loading: _loading,
                ),

                const SizedBox(height: 24),

                // 💬 Resend Section (famous app UX style)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: 1.0,
                  child: Column(
                    children: [
                      const Text(
                        "Didn't receive the code?",
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _canResend ? _onResendOtp : null,
                        child: Text(
                          _canResend
                              ? 'Resend OTP'
                              : 'Resend in ${_secondsRemaining.toString().padLeft(2, '0')}s',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _canResend
                                ? TWCColors.coffeeDark
                                : Colors.grey.shade600,
                            fontSize: 15,
                            decoration:
                            _canResend ? TextDecoration.underline : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
