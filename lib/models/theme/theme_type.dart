import 'package:flutter/material.dart';

enum ThemeType {
  light('浅色'),
  dark('深色'),
  system('跟随系统'),
  ;

  final String label;
  const ThemeType(this.label);

  ThemeMode get toThemeMode => switch (this) {
        ThemeType.light => ThemeMode.light,
        ThemeType.dark => ThemeMode.dark,
        ThemeType.system => ThemeMode.system,
      };
}
