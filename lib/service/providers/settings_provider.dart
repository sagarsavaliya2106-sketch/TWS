import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls how frequently GPS is collected (in seconds)
final gpsIntervalProvider = StateProvider<int>((ref) => 15);
