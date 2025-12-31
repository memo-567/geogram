import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'config_service.dart';
import 'log_service.dart';

/// Service to persist and restore window position/size on desktop platforms
class WindowStateService with WindowListener {
  static final WindowStateService _instance = WindowStateService._internal();
  factory WindowStateService() => _instance;
  WindowStateService._internal();

  // Config keys
  static const String _keyWindowWidth = 'window.width';
  static const String _keyWindowHeight = 'window.height';
  static const String _keyWindowX = 'window.x';
  static const String _keyWindowY = 'window.y';
  static const String _keyIsMaximized = 'window.isMaximized';

  // Minimum dimensions
  static const double minWidth = 800.0;
  static const double minHeight = 600.0;

  // Default dimensions
  static const double defaultWidth = 1200.0;
  static const double defaultHeight = 800.0;

  final ConfigService _config = ConfigService();
  Timer? _saveDebounceTimer;
  bool _isMaximized = false;
  bool _isListening = false;

  /// Get saved window state from config
  Future<WindowState> getSavedState() async {
    final width = _config.getNestedValue(_keyWindowWidth);
    final height = _config.getNestedValue(_keyWindowHeight);
    final x = _config.getNestedValue(_keyWindowX);
    final y = _config.getNestedValue(_keyWindowY);
    final isMaximized = _config.getNestedValue(_keyIsMaximized, false) as bool;

    // Check if we have valid saved dimensions
    if (width == null || height == null) {
      return WindowState(
        size: const Size(defaultWidth, defaultHeight),
        position: null,
        shouldCenter: true,
        isMaximized: false,
      );
    }

    // Parse and clamp dimensions
    final parsedWidth = max((width as num).toDouble(), minWidth);
    final parsedHeight = max((height as num).toDouble(), minHeight);

    // Check if we have valid saved position
    if (x == null || y == null) {
      return WindowState(
        size: Size(parsedWidth, parsedHeight),
        position: null,
        shouldCenter: true,
        isMaximized: isMaximized,
      );
    }

    final parsedX = (x as num).toDouble();
    final parsedY = (y as num).toDouble();

    return WindowState(
      size: Size(parsedWidth, parsedHeight),
      position: Offset(parsedX, parsedY),
      shouldCenter: false,
      isMaximized: isMaximized,
    );
  }

  /// Validate window state against screen bounds
  Future<WindowState> validateState(WindowState state) async {
    // Clamp size to minimum
    final width = max(state.size.width, minWidth);
    final height = max(state.size.height, minHeight);
    final size = Size(width, height);

    // If no saved position, center the window
    if (state.position == null || state.shouldCenter) {
      return WindowState(
        size: size,
        position: null,
        shouldCenter: true,
        isMaximized: state.isMaximized,
      );
    }

    // Basic sanity check: position should be reasonable
    // We can't fully validate without screen info, but we can check for clearly invalid values
    final x = state.position!.dx;
    final y = state.position!.dy;

    // If position is extremely negative or very large, it's likely off-screen
    // Most monitors are less than 10000 pixels wide/tall
    if (x < -width || y < -height || x > 10000 || y > 10000) {
      LogService().log('Window position ($x, $y) seems off-screen, centering');
      return WindowState(
        size: size,
        position: null,
        shouldCenter: true,
        isMaximized: state.isMaximized,
      );
    }

    // Position seems reasonable, use it
    return WindowState(
      size: size,
      position: state.position,
      shouldCenter: false,
      isMaximized: state.isMaximized,
    );
  }

  /// Start listening for window changes
  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;
    windowManager.addListener(this);
    _isMaximized = await windowManager.isMaximized();
    LogService().log('WindowStateService: Started listening for window changes');
  }

  /// Stop listening for window changes
  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    windowManager.removeListener(this);
    _saveDebounceTimer?.cancel();
  }

  /// Save current window state (debounced)
  void _saveStateDebounced() {
    // Don't save while maximized (we want to remember the un-maximized size)
    if (_isMaximized) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _saveCurrentState();
    });
  }

  /// Save current window state immediately
  Future<void> _saveCurrentState() async {
    try {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      _config.setNestedValue(_keyWindowWidth, size.width);
      _config.setNestedValue(_keyWindowHeight, size.height);
      _config.setNestedValue(_keyWindowX, position.dx);
      _config.setNestedValue(_keyWindowY, position.dy);

      LogService().log('WindowStateService: Saved window state - ${size.width}x${size.height} at (${position.dx}, ${position.dy})');
    } catch (e) {
      LogService().log('WindowStateService: Error saving window state: $e');
    }
  }

  /// Save maximized state
  void _saveMaximizedState(bool maximized) {
    _isMaximized = maximized;
    _config.setNestedValue(_keyIsMaximized, maximized);
    LogService().log('WindowStateService: Saved maximized state: $maximized');
  }

  // WindowListener callbacks

  @override
  void onWindowResized() {
    _saveStateDebounced();
  }

  @override
  void onWindowMoved() {
    _saveStateDebounced();
  }

  @override
  void onWindowMaximize() {
    _saveMaximizedState(true);
  }

  @override
  void onWindowUnmaximize() {
    _saveMaximizedState(false);
    // Save the unmaximized size/position after a short delay
    Timer(const Duration(milliseconds: 100), () {
      _saveStateDebounced();
    });
  }

  @override
  void onWindowClose() {
    // Save state one more time before closing
    _saveDebounceTimer?.cancel();
    _saveCurrentState();
  }

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}

  @override
  void onWindowDocked() {}

  @override
  void onWindowUndocked() {}
}

/// Represents the window state (size, position, maximized)
class WindowState {
  final Size size;
  final Offset? position;
  final bool shouldCenter;
  final bool isMaximized;

  WindowState({
    required this.size,
    this.position,
    required this.shouldCenter,
    required this.isMaximized,
  });
}
