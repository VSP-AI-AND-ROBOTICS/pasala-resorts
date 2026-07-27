import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF2E6B4F),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
