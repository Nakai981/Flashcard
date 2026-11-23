import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChibiTheme {
  // Bảng màu Xanh Dương iPhone 15 Plus (Pastel Ice Blue / Frost Blue)
  static const Color bgCream = Color(0xFFF3F8FD); // Nền trắng xanh băng dịu mắt
  static const Color pastelPink = Color(0xFF66A8FF); // Xanh dương pastel chủ đạo (iPhone 15 Plus Blue accent)
  static const Color softPink = Color(0xFFD6E9FF); // Xanh băng nhạt (iPhone 15 Plus Ice Blue body)
  static const Color deepPink = Color(0xFF2B72D6); // Xanh dương đậm nổi bật cho nút chính & tiêu đề
  static const Color pastelLavender = Color(0xFF93C5FD); // Xanh sky pastel
  static const Color softLavender = Color(0xFFE5F1FF); // Xanh sương mù nhạt
  static const Color pastelMint = Color(0xFF7DD3FC); // Xanh cyan băng
  static const Color softMint = Color(0xFFE0F7FE); // Nền xanh cyan nhạt
  static const Color pastelMatcha = Color(0xFF4ADE80); // Xanh lá báo đúng
  static const Color pastelYellow = Color(0xFFBAE6FD);
  static const Color textDark = Color(0xFF1E324A); // Xanh navy đậm dễ đọc
  static const Color textMuted = Color(0xFF5C7696); // Xanh xám dịu

  static ThemeData buildTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgCream,
      fontFamily: GoogleFonts.quicksand().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: pastelPink,
        primary: pastelPink,
        secondary: pastelLavender,
        surface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.quicksand(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textDark,
        ),
        iconTheme: const IconThemeData(color: textDark),
      ),
    );
  }

  static BoxDecoration kawaiiCardDecoration({
    Color color = Colors.white,
    Color borderColor = softPink,
    double radius = 28,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 2.5),
      boxShadow: [
        BoxShadow(
          color: borderColor.withValues(alpha: 0.55),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
