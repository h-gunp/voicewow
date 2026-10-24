import 'package:flutter/material.dart';

const ink = Color(0xff172b4d),
    muted = Color(0xff5d6d82),
    blue = Color(0xff2f62d6),
    canvas = Color(0xfff8f9f7),
    line = Color(0xffd8e0e8),
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
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: ink,
    displayColor: ink,
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
