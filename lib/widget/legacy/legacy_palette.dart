import 'package:flutter/material.dart';

class LegacyPalette {
  static Color bg0(bool light) =>
      light ? const Color(0xFFF5F6F7) : const Color(0xFF141414);
  static Color bg1(bool light) =>
      light ? Colors.white : const Color(0xFF1A1A1A);
  static Color bg2(bool light) =>
      light ? const Color(0xFFF0F2F4) : const Color(0xFF202020);
  static Color bg3(bool light) =>
      light ? const Color(0xFFE7EBEE) : const Color(0xFF272727);
  static Color border(bool light) =>
      light ? const Color(0xFFDCE0E4) : const Color(0xFF2A2A2A);
  static Color borderStrong(bool light) =>
      light ? const Color(0xFFC3CBD2) : const Color(0xFF333333);
  static Color text(bool light) =>
      light ? const Color(0xFF1F2933) : const Color(0xFFE4E7EA);
  static Color text2(bool light) =>
      light ? const Color(0xFF46525F) : const Color(0xFFBDC3C9);
  static Color text3(bool light) =>
      light ? const Color(0xFF5E6974) : const Color(0xFFA3ADB7);
  static Color accent(bool light) =>
      light ? const Color(0xFF087D60) : const Color(0xFF28B790);
  static Color accentBg(bool light) =>
      light ? const Color.fromRGBO(8, 125, 96, .075) : const Color.fromRGBO(40, 183, 144, .10);
  static Color selected(bool light) =>
      light ? const Color.fromRGBO(8, 125, 96, .10) : const Color.fromRGBO(40, 183, 144, .12);
  static Color hover(bool light) =>
      light ? const Color.fromRGBO(31, 41, 51, .045) : const Color.fromRGBO(255, 255, 255, .045);
  static Color error(bool light) =>
      light ? const Color(0xFFB42318) : const Color(0xFFFF8585);
  static Color rowBorder(bool light) =>
      light ? const Color(0xFFE8ECEF) : const Color(0xFF252A2D);
  static Color button(bool light) => const Color(0xFF087D60);
}
