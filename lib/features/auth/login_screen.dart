import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:untitled/widgets/twc_toast.dart';

import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../widgets/twc_logo_header.dart';
import '../../widgets/twc_primary_button.dart';
import '../../widgets/twc_input_field.dart';
import '../../widgets/twc_footer.dart';
import '../../utils/validators.dart';
import '../../service/providers/auth_provider.dart';
import 'otp_screen.dart';

final loginLoadingProvider = StateProvider<bool>((ref) => false);
final loginErrorProvider = StateProvider<String?>((ref) => null);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _mobileCtrl = TextEditingController();

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSendOtp() async {
    final mobile = _mobileCtrl.text.trim();
    ref.read(loginErrorProvider.notifier).state = null;

    if (!isValidMobile(mobile)) {
      showTwcToast(context, 'Please enter a valid 10-digit mobile number', isError: true);
      return;
    }

    ref.read(loginLoadingProvider.notifier).state = true;

    final result = await ref.read(authNotifierProvider.notifier).sendOtp(mobile);

    ref.read(loginLoadingProvider.notifier).state = false;

    if (result['ok'] == true) {
      await ref.read(authNotifierProvider.notifier).setMobileOnly(mobile);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(mobile: mobile)));
    } else {
      final msg = result['message'] ?? 'Failed to send OTP';
      showTwcToast(context, msg, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(loginLoadingProvider);
    final errorText = ref.watch(loginErrorProvider);

    return Scaffold(
      backgroundColor: TWCColors.latteBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const TWCLogoHeader(size: 92),
                const SizedBox(height: 20),
                Text('Driver Login', style: TWCTextStyles.heading),
                const SizedBox(height: 6),
                Text('Enter your mobile number to continue', style: TWCTextStyles.subtitle, textAlign: TextAlign.center),
                const SizedBox(height: 22),

                TWCInputField(controller: _mobileCtrl, hint: 'Mobile number', onChanged: (_) {
                  if (ref.read(loginErrorProvider) != null) {
                    ref.read(loginErrorProvider.notifier).state = null;
                  }
                }),

                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],

                const SizedBox(height: 20),

                TWCPrimaryButton(label: 'Send OTP', onPressed: _onSendOtp, loading: loading),

                const SizedBox(height: 36),

                const TWCFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
