import 'package:flutter/material.dart';

const ink = Color(0xff252a27),
    muted = Color(0xff626b65),
    accent = Color(0xff315b49),
    blue = accent,
    canvas = Color(0xfffafaf7),
    line = Color(0xffd9ddd7),
    wash = Color(0xffedf2ec),
    red = Color(0xffad3d38);

const pageTitle = TextStyle(
  fontSize: 30,
  fontWeight: FontWeight.w700,
  letterSpacing: -1,
  height: 1.3,
);
const sectionTitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
const bodyCopy = TextStyle(color: muted, fontSize: 16, height: 1.7);
const smallCopy = TextStyle(color: muted, fontSize: 14, height: 1.7);

ThemeData buildAppTheme() {
  final textTheme = ThemeData.light().textTheme
      .apply(fontFamily: 'Pretendard', bodyColor: ink, displayColor: ink)
      .copyWith(
        bodyLarge: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          height: 1.6,
          color: ink,
        ),
        bodyMedium: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          height: 1.6,
          color: ink,
        ),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      surface: canvas,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Pretendard',
    textTheme: textTheme,
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge!.copyWith(
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: wash,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        textStyle: textTheme.labelLarge!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: line),
        textStyle: textTheme.labelLarge!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(48, 48),
        textStyle: textTheme.labelLarge!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}
