import 'package:flutter/material.dart';

class AppPallete {
  // Ayurvedic theme colors from the provided image
  static const Color primaryColor = Color(0xFF5E7C6A); // Primary (green)
  static const Color secondaryColor =
      Color(0xFFF9F4E4); // Secondary (light cream)
  static const Color accentColor = Color(0xFFB97A56); // Accent (brown)
  static const Color highlightColor = Color(0xFFF7CBA4); // Highlight (peach)
  static const Color textColor = Color(0xFF3C3936); // Text (dark brown/black)

  static const Color borderColor = Color(0xFFB97A56); // Use accent for borders
  static const Color whiteColor = Colors.white;
  static const Color greyColor = Colors.grey;
  static const Color errorColor = Colors.redAccent;
  static const Color transparentColor = Colors.transparent;
  static const Color backgroundColor =
      Color(0xFFF9F4E4); // Use secondary as background

  // Gradients using ayurvedic palette
  static const gradient1 = primaryColor;
  static const gradient2 = accentColor;
  static const gradient3 = highlightColor;

  static const Color fadeprimary = highlightColor;
  static const Color primaryFgColor = primaryColor;
  static const Color accentFgColor = accentColor;
  static const Color secondaryFgColor = secondaryColor;
}
