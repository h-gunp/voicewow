import 'package:flutter/material.dart';

const ink = Color(0xff172b4d),
    muted = Color(0xff52647b),
    blue = Color(0xff2f62d6),
    canvas = Color(0xfff1f5fc),
    line = Color(0xffcbd8ea),
    wash = Color(0xffedf3ff),
    red = Color(0xffb63a43);

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    surface: canvas,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: canvas,
  fontFamily: 'Pretendard',
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: const Color(0xeefbfcff),
    indicatorColor: const Color(0xffdce8ff),
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
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
  ),
  textTheme: ThemeData.light().textTheme
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
          fontSize: 14,
          height: 1.6,
          color: ink,
        ),
      ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: blue,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 54),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(double.infinity, 52),
      padding: const EdgeInsets.all(16),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);

// A static pastel backdrop keeps the glass treatment inexpensive while listening.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffe9f2ff), Color(0xfff1f5fc), Color(0xffeeeafa)],
      ),
    ),
    child: child,
  );
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: MediaQuery.highContrastOf(context) ? Colors.white : null,
      gradient: MediaQuery.highContrastOf(context)
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xfaffffff), Color(0xeef9fbff)],
            ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xffd5e0ef)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1224467a),
          blurRadius: 30,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}
