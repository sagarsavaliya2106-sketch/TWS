import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AttendanceUiState {
  final bool isLoading;
  final bool isPressed;
  final int countdown;
  final bool checkedIn;

  const AttendanceUiState({
    this.isLoading = false,
    this.isPressed = false,
    this.countdown = 0,
    this.checkedIn = false,
  });

  AttendanceUiState copyWith({
    bool? isLoading,
    bool? isPressed,
    int? countdown,
    bool? checkedIn,
  }) {
    return AttendanceUiState(
      isLoading: isLoading ?? this.isLoading,
      isPressed: isPressed ?? this.isPressed,
      countdown: countdown ?? this.countdown,
      checkedIn: checkedIn ?? this.checkedIn,
    );
  }
}

class AttendanceUiNotifier extends StateNotifier<AttendanceUiState> {
  AttendanceUiNotifier() : super(const AttendanceUiState());

  Timer? _countdownTimer;

  void setPressed(bool value) => state = state.copyWith(isPressed: value);
  void setLoading(bool value) => state = state.copyWith(isLoading: value);
  void toggleCheckedIn() => state = state.copyWith(checkedIn: !state.checkedIn);

  Future<void> startCountdown(int seconds) async {
    _countdownTimer?.cancel();
    for (int i = seconds; i > 0; i--) {
      state = state.copyWith(countdown: i);
      await Future.delayed(const Duration(seconds: 1));
    }
    state = state.copyWith(countdown: 0, isLoading: false);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void forceCheckedOut() {
    state = state.copyWith(checkedIn: false, isLoading: false);
  }

  void forceCheckedIn(bool value) => state = state.copyWith(checkedIn: value);
}

final attendanceUiProvider =
StateNotifierProvider<AttendanceUiNotifier, AttendanceUiState>(
      (ref) => AttendanceUiNotifier(),
);

final dutyToggleProvider = StateProvider<bool>((ref) => false);

// true while /duty API call is in-flight (disable the switch)
final dutyApiLoadingProvider = StateProvider<bool>((ref) => false);
