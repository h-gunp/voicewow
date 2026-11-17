import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

const ink = Color(0xff172b34),
    muted = Color(0xff536974),
    accent = Color(0xff176b67),
    blue = accent,
    canvas = Color(0xfff2f5f7),
    line = Color(0xffd7e2e6),
    wash = Color(0xffe3efed),
    red = Color(0xffb44343);

const pageTitle = TextStyle(
  fontSize: 32,
  fontWeight: FontWeight.w700,
  letterSpacing: -1.2,
  height: 1.3,
);
const sectionTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
const bodyCopy = TextStyle(color: muted, fontSize: 16, height: 1.7);
const smallCopy = TextStyle(color: muted, fontSize: 14, height: 1.7);
const springCurve = Cubic(.16, 1, .3, 1);

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
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: accent,
          surface: canvas,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          onPrimary: Colors.white,
          secondary: accent,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: line,
          surfaceContainerHighest: wash,
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
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: wash,
      height: 74,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        textStyle: textTheme.labelLarge!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: Colors.white.withValues(alpha: .6),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: line),
        textStyle: textTheme.labelLarge!.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
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
        shape: const StadiumBorder(),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: wash,
      side: const BorderSide(color: line),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontFamily: 'Pretendard',
        color: ink,
        fontSize: 14,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: wash,
    ),
  );
}

// Scrolling surfaces keep depth without a live backdrop filter.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.tint,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, tint ?? const Color(0xffeaf0f2)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .95)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0b244653),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    padding: const EdgeInsets.all(3),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: (tint ?? Colors.white).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(radius - 3),
        border: Border.all(color: Colors.white.withValues(alpha: .85)),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

// Only fixed app chrome uses backdrop blur.
class LiquidChrome extends StatelessWidget {
  const LiquidChrome({super.key, required this.child, this.radius = 30});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x13244653),
          blurRadius: 32,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xf2ffffff), Color(0xe6edf3f5)],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: .95)),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class VoiceMark extends StatelessWidget {
  const VoiceMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .29),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff368e87), Color(0xff104d51)],
        ),
        border: Border.all(color: const Color(0xff71aaa5), width: .7),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final height in [.22, .43, .6, .43, .22])
              Container(
                width: size * .075,
                height: size * height,
                margin: EdgeInsets.symmetric(horizontal: size * .025),
                decoration: BoxDecoration(
                  color: const Color(0xffe6f5f1),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
