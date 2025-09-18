import 'dart:async';
import 'package:flutter/material.dart';

/// Show a top-level toast using the app Overlay.
///
/// Returns a function you can call to remove the toast early:
///   final dismiss = showTwcToast(context, 'Saved');
///   dismiss();
///
/// If you prefer to await auto-dismissal, await the returned Future:
///   await showTwcToast(context, 'Saved');
Future<void> showTwcToast(
    BuildContext context,
    String message, {
      bool isError = false,
      Duration duration = const Duration(seconds: 3),
    }) async {
  final overlay = Overlay.of(context);

  final bg = isError ? Colors.red.shade600 : Colors.green.shade600;
  final textColor = Colors.white;

  final entry = OverlayEntry(
    builder: (ctx) {
      // positioned above bottom padding (navigation bars, etc.)
      return Positioned(
        bottom: 36 + MediaQuery.of(ctx).viewPadding.bottom,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 240),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 6))],
              ),
              child: Row(
                children: [
                  Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: textColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(fontFamily: 'Lato', color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
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

  // Insert
  overlay.insert(entry);

  // auto remove
  await Future.delayed(duration);

  try {
    entry.remove();
  } catch (_) {}
}
