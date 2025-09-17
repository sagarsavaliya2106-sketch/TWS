import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

class TWCInputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final bool showPrefix;
  final ValueChanged<String>? onChanged;

  const TWCInputField({
    super.key,
    required this.controller,
    this.hint = '',
    this.maxLength = 10,
    this.showPrefix = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        maxLength: maxLength,
        style: GoogleFonts.merriweather(fontSize: 15, letterSpacing: 1.0, color: TWCColors.coffeeDark),
        decoration: InputDecoration(
          counterText: '',
          prefixIcon: showPrefix
              ? Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('+91', style: GoogleFonts.lato(fontWeight: FontWeight.w600, color: TWCColors.coffeeDark)),
                const SizedBox(width: 6),
                Container(width: 1, height: 26, color: Colors.grey.shade300),
              ],
            ),
          )
              : null,
          filled: true,
          fillColor: Colors.white,
          hintText: hint,
          hintStyle: GoogleFonts.merriweather(color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
