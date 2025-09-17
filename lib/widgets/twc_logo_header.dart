import 'package:flutter/material.dart';

class TWCLogoHeader extends StatelessWidget {
  final double size;
  const TWCLogoHeader({super.key, this.size = 90});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // fallback if asset missing
          return Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: const Icon(Icons.local_cafe, size: 40, color: Color(0xFF2D3C4B)),
          );
        },
      ),
    );
  }
}
