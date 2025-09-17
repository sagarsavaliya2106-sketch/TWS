import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:untitled/service/api_service.dart';

/// Provide ApiService instance — set baseUrl to your staging/production host
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService('https://twcstaging.forklyft.in'); // change if needed
});

/// Auth state
class AuthState {
  final String? mobile;
  final bool loggedIn;
  AuthState({this.mobile, this.loggedIn = false});

  AuthState copyWith({String? mobile, bool? loggedIn}) {
    return AuthState(
      mobile: mobile ?? this.mobile,
      loggedIn: loggedIn ?? this.loggedIn,
    );
  }
}

/// AuthNotifier with all required methods used by UI
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService api;
  AuthNotifier(this.api) : super(AuthState());

  /// Set mobile locally (Login screen uses this without hitting server)
  Future<void> setMobileOnly(String mobile) async {
    state = state.copyWith(mobile: mobile, loggedIn: false);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('mobile_temp', mobile);
  }

  /// Verify mobile using TWC driver API
  /// Returns a map {ok:bool, message:String?, data:Map?}
  Future<Map<String, dynamic>> verifyMobileOnServer() async {
    final mobile = state.mobile;
    if (mobile == null) return {'ok': false, 'message': 'No mobile provided'};

    try {
      final resp = await api.driverLogin(mobile);
      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final status = data['status']?.toString();
        if (status == 'success') {
          return {'ok': true, 'data': data};
        } else {
          final message = data['message']?.toString() ?? 'Mobile not registered';
          return {'ok': false, 'message': message};
        }
      } else {
        return {'ok': false, 'message': 'Unexpected server response'};
      }
    } on DioException catch (e) {
      String? message = e.message;
      if (e.response != null) {
        final d = e.response!.data;
        if (d is Map && d['message'] != null) message = d['message'].toString();
      }
      return {'ok': false, 'message': message};
    } catch (e) {
      return {'ok': false, 'message': e.toString()};
    }
  }

  /// Mark login complete and persist mobile
  Future<void> completeLogin() async {
    state = state.copyWith(loggedIn: true);
    final sp = await SharedPreferences.getInstance();
    final mobile = state.mobile;
    if (mobile != null) {
      await sp.setString('mobile', mobile);
      await sp.remove('mobile_temp');
    }
  }

  /// Logout: clear saved mobile and reset state
  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('mobile');
    await sp.remove('mobile_temp');
    state = AuthState();
  }

  /// Restore saved mobile (called at app start)
  Future<void> restoreFromPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString('mobile');
    if (saved != null && saved.isNotEmpty) {
      state = state.copyWith(mobile: saved, loggedIn: true);
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
