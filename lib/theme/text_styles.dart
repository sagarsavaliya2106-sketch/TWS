import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class TWCTextStyles {
  static final heading = GoogleFonts.lato(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: TWCColors.coffeeDark,
  );

  static final subtitle = GoogleFonts.merriweather(
    fontSize: 14,
    color: TWCColors.greyText,
  );

  static final button = GoogleFonts.lato(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static final footer = GoogleFonts.merriweather(
    fontSize: 12,
    color: Colors.grey,
  );
}
