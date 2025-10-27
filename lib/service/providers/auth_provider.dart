import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/service/api_service.dart';

/// Provide ApiService instance — set baseUrl to your staging/production host
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService('https://twcstaging.forklyft.in');
  // return ApiService('https://twc.forklyft.in');
});

/// Auth state
class AuthState {
  final String? mobile;
  final bool loggedIn;
  final String? employeeId;
  final String? employeeName;

  AuthState({
    this.mobile,
    this.loggedIn = false,
    this.employeeId,
    this.employeeName,
  });

  AuthState copyWith({
    String? mobile,
    bool? loggedIn,
    String? employeeId,
    String? employeeName,
  }) {
    return AuthState(
      mobile: mobile ?? this.mobile,
      loggedIn: loggedIn ?? this.loggedIn,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
    );
  }
}

/// AuthNotifier with all required methods used by UI
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService api;
  AuthNotifier(this.api) : super(AuthState());

  Future<void> setMobileOnly(String mobile) async {
    state = state.copyWith(mobile: mobile, loggedIn: false);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('mobile_temp', mobile);
  }

  /// Step 1: Send OTP
  Future<Map<String, dynamic>> sendOtp(String mobile) async {
    try {
      final resp = await api.sendOtp(mobile);
      final data = resp.data;
      if (data is Map && data['result'] is Map) {
        final result = data['result'] as Map;
        final status = result['status']?.toString();
        final message = result['message']?.toString();
        return {'ok': status == 'success', 'message': message};
      }
      return {'ok': false, 'message': 'Unexpected server response'};
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }

  /// Step 2: Verify OTP
  Future<Map<String, dynamic>> verifyOtp(String mobile, String otp) async {
    try {
      final resp = await api.verifyOtp(mobile, otp);
      final data = resp.data;
      if (data is Map && data['result'] is Map) {
        final result = data['result'] as Map;
        final status = result['status']?.toString();
        final message = result['message']?.toString();
        return {'ok': status == 'success', 'message': message};
      }
      return {'ok': false, 'message': 'Unexpected server response'};
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }

  Future<void> completeLogin({String? mobile, String? employeeId, String? employeeName}) async {
    // ✅ Ensure mobile is kept from state or passed explicitly
    final finalMobile = mobile ?? state.mobile;

    state = state.copyWith(
      mobile: finalMobile,
      loggedIn: true,
      employeeId: employeeId,
      employeeName: employeeName,
    );

    final sp = await SharedPreferences.getInstance();
    if (finalMobile != null && finalMobile.isNotEmpty) {
      await sp.setString('mobile', finalMobile);
      await sp.remove('mobile_temp');
    }
    if (employeeId != null) await sp.setString('employee_id', employeeId);
    if (employeeName != null) await sp.setString('employee_name', employeeName);
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    state = AuthState();
  }

  Future<void> restoreFromPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final savedMobile = sp.getString('mobile');
    final savedId = sp.getString('employee_id');
    final savedName = sp.getString('employee_name');

    if (savedMobile != null && savedMobile.isNotEmpty) {
      state = state.copyWith(
        mobile: savedMobile,
        loggedIn: true,
        employeeId: savedId,
        employeeName: savedName,
      );
    }
  }
}

/// Providers
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthNotifier(api);
});

/// Startup provider to restore auth from shared preferences at app launch
final authRestoreProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(authNotifierProvider.notifier);
  await notifier.restoreFromPrefs();
});
