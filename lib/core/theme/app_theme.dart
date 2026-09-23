import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Reference Inspired Luxury Mint Light Palette
  static const resortMintBg = Color(0xFFEDF6F2); // Soft mint / very-light-green canvas
  static const resortEmerald = Color(0xFF10B981); // Vibrant green/teal for price badges & accents
  static const resortDarkGreen = Color(0xFF047857); // Deep forest green accent
  static const resortBlack = Color(0xFF111827); // Dark black/charcoal for CTA buttons
  static const resortDarkText = Color(0xFF111827); // Dark text
  static const resortMutedText = Color(0xFF6B7280); // Muted gray text
  static const resortBorder = Color(0xFFE5E7EB); // Subtle border
  static const resortSoftGreen = Color(0xFFD1FAE5); // Soft green pill background
  static const resortGold = Color(0xFFF59E0B); // Gold star rating accent

  // Reference Inspired Luxury Mint Dark Palette
  static const resortDarkBg = Color(0xFF0D1512); // Deep dark forest slate canvas
  static const resortDarkSurface = Color(0xFF16221D); // Dark elevated surface / card
  static const resortDarkSurfaceHighlight = Color(0xFF1E2E28); // Lighter dark card / container
  static const resortDarkBorder = Color(0xFF263A32); // Dark subtle border
  static const resortDarkTextLight = Color(0xFFF9FAFB); // Primary text in dark mode
  static const resortDarkMuted = Color(0xFF9CA3AF); // Muted text in dark mode

  // Compatibility Mappings
  static const resortMintPrimary = resortEmerald;
  static const resortCharcoal = resortBlack;
  static const resortCoral = resortEmerald;
  static const resortSandBg = resortMintBg;
  static const bookingNavy = resortBlack;
  static const bookingActionBlue = resortEmerald;
  static const bookingYellow = resortGold;
  static const bookingDarkText = resortDarkText;
  static const bookingBgLight = resortMintBg;
  static const bookingBorder = resortBorder;

  // Legacy Compatibility Aliases
  static const primaryNavy = resortBlack;
  static const primaryTeal = resortDarkGreen;
  static const primarySlate = Color(0xFF1F2937);
  static const accentAmber = resortGold;

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

  static void toggleTheme() {
    themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  // Helper Methods for Dynamic Responsive Styling across Light & Dark Mode
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color cardBg(BuildContext context) => isDark(context) ? resortDarkSurface : Colors.white;
  static Color pageBg(BuildContext context) => isDark(context) ? resortDarkBg : resortMintBg;
  static Color textPrimary(BuildContext context) => isDark(context) ? resortDarkTextLight : resortDarkText;
  static Color textMuted(BuildContext context) => isDark(context) ? resortDarkMuted : resortMutedText;
  static Color border(BuildContext context) => isDark(context) ? resortDarkBorder : resortBorder;
  static Color pillBg(BuildContext context) => isDark(context) ? resortDarkSurfaceHighlight : Colors.white;
  static Color ctaBg(BuildContext context) => isDark(context) ? resortEmerald : resortBlack;
  static Color ctaText(BuildContext context) => Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: resortMintBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: resortEmerald,
        brightness: Brightness.light,
        primary: resortBlack,
        secondary: resortEmerald,
        surface: Colors.white,
        onSurface: resortDarkText,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().apply(
        bodyColor: resortDarkText,
        displayColor: resortDarkText,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: resortDarkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: resortDarkText,
        ),
        iconTheme: const IconThemeData(color: resortDarkText),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: resortBorder, width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: resortBlack,
        unselectedItemColor: resortMutedText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortEmerald, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: resortEmerald,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        side: const BorderSide(color: resortBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: resortDarkText),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: resortDarkBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: resortEmerald,
        brightness: Brightness.dark,
        primary: resortEmerald,
        secondary: resortGold,
        surface: resortDarkSurface,
        onSurface: resortDarkTextLight,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: resortDarkTextLight,
        displayColor: resortDarkTextLight,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: resortDarkTextLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: resortDarkTextLight,
        ),
        iconTheme: const IconThemeData(color: resortDarkTextLight),
      ),
      cardTheme: CardThemeData(
        color: resortDarkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: resortDarkBorder, width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: resortDarkSurface,
        selectedItemColor: resortEmerald,
        unselectedItemColor: resortDarkMuted,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: resortDarkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortDarkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortDarkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: resortEmerald, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: resortEmerald,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: resortDarkSurface,
        side: const BorderSide(color: resortDarkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: resortDarkTextLight),
      ),
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  return brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
}
