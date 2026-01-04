/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Service for managing the app's Material theme colors, fonts, and backgrounds.
 */

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'config_service.dart';

/// Available app theme options
enum AppThemeColor {
  blue,
  red,
  amber,
  green,
}

/// Available font options
enum AppFont {
  system,
  roboto,
  openSans,
  lato,
  montserrat,
}

/// Theme configuration with color and display info
class AppThemeConfig {
  final AppThemeColor id;
  final String name;
  final Color seedColor;
  final Color? darkSeedColor;

  const AppThemeConfig({
    required this.id,
    required this.name,
    required this.seedColor,
    this.darkSeedColor,
  });
}

/// Service for managing app theme colors
class AppThemeService extends ChangeNotifier {
  static final AppThemeService _instance = AppThemeService._internal();
  factory AppThemeService() => _instance;
  AppThemeService._internal();

  static const String _themeKey = 'settings.appTheme';
  static const String _fontKey = 'settings.appFont';
  static const String _bgColorKey = 'settings.backgroundColor';
  static const String _bgImageKey = 'settings.backgroundImage';

  /// Black background color for dark themes
  static const Color _darkBackground = Color(0xFF0A0A0A);
  static const Color _darkSurface = Color(0xFF121212);
  static const Color _darkSurfaceContainer = Color(0xFF1E1E1E);

  /// Available themes
  static const List<AppThemeConfig> availableThemes = [
    AppThemeConfig(
      id: AppThemeColor.blue,
      name: 'Blue',
      seedColor: Colors.blue,
    ),
    AppThemeConfig(
      id: AppThemeColor.red,
      name: 'Red',
      seedColor: Colors.red,
    ),
    AppThemeConfig(
      id: AppThemeColor.amber,
      name: 'Amber',
      seedColor: Colors.amber,
    ),
    AppThemeConfig(
      id: AppThemeColor.green,
      name: 'Green',
      seedColor: Color(0xFF00C853),
      darkSeedColor: Color(0xFF00E676),
    ),
  ];

  /// Available background colors
  static const List<Color> availableBackgroundColors = [
    Color(0xFF0A0A0A), // Default black
    Color(0xFF1A1A2E), // Dark blue
    Color(0xFF16213E), // Navy
    Color(0xFF1B1B1B), // Charcoal
    Color(0xFF2D132C), // Dark purple
    Color(0xFF1E3A3A), // Dark teal
  ];

  /// Font family names
  static const Map<AppFont, String?> fontFamilies = {
    AppFont.system: null,
    AppFont.roboto: 'Roboto',
    AppFont.openSans: 'OpenSans',
    AppFont.lato: 'Lato',
    AppFont.montserrat: 'Montserrat',
  };

  AppThemeColor _currentTheme = AppThemeColor.blue;
  AppFont _currentFont = AppFont.system;
  Color? _backgroundColor;
  String? _backgroundImage;

  /// Get the current theme
  AppThemeColor get currentTheme => _currentTheme;

  /// Get the current font
  AppFont get currentFont => _currentFont;

  /// Get the current background color
  Color? get backgroundColor => _backgroundColor;

  /// Get the current background image
  String? get backgroundImage => _backgroundImage;

  /// Check if background image exists
  bool get hasValidBackgroundImage {
    if (_backgroundImage == null || _backgroundImage!.isEmpty) return false;
    if (kIsWeb) return false;
    return File(_backgroundImage!).existsSync();
  }

  /// Get the current theme config
  AppThemeConfig get currentConfig =>
      availableThemes.firstWhere((t) => t.id == _currentTheme);

  /// Initialize the service and load saved settings
  Future<void> initialize() async {
    final config = ConfigService();

    // Load theme
    final savedTheme = config.getNestedValue(_themeKey);
    if (savedTheme is String) {
      try {
        final themeName = savedTheme == 'cybergreen' ? 'green' : savedTheme;
        _currentTheme = AppThemeColor.values.firstWhere(
          (t) => t.name == themeName,
          orElse: () => AppThemeColor.blue,
        );
      } catch (_) {
        _currentTheme = AppThemeColor.blue;
      }
    }

    // Load font
    final savedFont = config.getNestedValue(_fontKey);
    if (savedFont is String) {
      try {
        _currentFont = AppFont.values.firstWhere(
          (f) => f.name == savedFont,
          orElse: () => AppFont.system,
        );
      } catch (_) {
        _currentFont = AppFont.system;
      }
    }

    // Load background color
    final savedBgColor = config.getNestedValue(_bgColorKey);
    if (savedBgColor is int) {
      _backgroundColor = Color(savedBgColor);
    }

    // Load background image
    final savedBgImage = config.getNestedValue(_bgImageKey);
    if (savedBgImage is String && savedBgImage.isNotEmpty) {
      _backgroundImage = savedBgImage;
    }
  }

  /// Set the current theme
  Future<void> setTheme(AppThemeColor theme) async {
    if (_currentTheme == theme) return;
    _currentTheme = theme;
    ConfigService().setNestedValue(_themeKey, theme.name);
    notifyListeners();
  }

  /// Set the current font
  Future<void> setFont(AppFont font) async {
    if (_currentFont == font) return;
    _currentFont = font;
    ConfigService().setNestedValue(_fontKey, font.name);
    notifyListeners();
  }

  /// Set the background color
  Future<void> setBackgroundColor(Color? color) async {
    _backgroundColor = color;
    if (color != null) {
      ConfigService().setNestedValue(_bgColorKey, color.value);
    } else {
      ConfigService().setNestedValue(_bgColorKey, null);
    }
    notifyListeners();
  }

  /// Set the background image
  Future<void> setBackgroundImage(String? path) async {
    _backgroundImage = path;
    ConfigService().setNestedValue(_bgImageKey, path);
    notifyListeners();
  }

  /// Clear background image
  Future<void> clearBackgroundImage() async {
    _backgroundImage = null;
    ConfigService().setNestedValue(_bgImageKey, null);
    notifyListeners();
  }

  /// Get the effective background color for dark theme
  Color getEffectiveBackgroundColor() {
    return _backgroundColor ?? _darkBackground;
  }

  /// Get the light theme data for the current theme
  ThemeData getLightTheme() {
    final config = currentConfig;
    final fontFamily = fontFamilies[_currentFont];

    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: config.seedColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: fontFamily,
    );
  }

  /// Get the dark theme data for the current theme
  ThemeData getDarkTheme() {
    final config = currentConfig;
    final seedColor = config.darkSeedColor ?? config.seedColor;
    final fontFamily = fontFamilies[_currentFont];
    final bgColor = _backgroundColor ?? _darkBackground;

    // Create base color scheme
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    // Override with custom or default background
    final colorScheme = baseScheme.copyWith(
      surface: _darkSurface,
      surfaceContainerLowest: bgColor,
      surfaceContainerLow: const Color(0xFF161616),
      surfaceContainer: _darkSurfaceContainer,
      surfaceContainerHigh: const Color(0xFF242424),
      surfaceContainerHighest: const Color(0xFF2A2A2A),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: _darkSurfaceContainer,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: _darkSurface,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _darkSurface,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _darkSurface,
      ),
    );
  }
}
