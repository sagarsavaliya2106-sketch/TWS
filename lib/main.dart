// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'service/providers/api_and_auth.dart';
import 'theme/colors.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoreAsync = ref.watch(authRestoreProvider);

    return MaterialApp(
      title: 'TWC Driver',
      theme: ThemeData(
        primaryColor: TWCColors.coffeeDark,
        scaffoldBackgroundColor: TWCColors.latteBg,
      ),
      home: restoreAsync.when(
        data: (_) {
          final auth = ref.read(authNotifierProvider);
          if (auth.loggedIn == true && (auth.mobile?.isNotEmpty ?? false)) {
            return const DashboardScreen();
          } else {
            return const LoginScreen();
          }
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (err, st) {
          // fallback to login screen on error
          return const LoginScreen();
        },
      ),
    );
  }
}
