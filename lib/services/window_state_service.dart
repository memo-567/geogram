import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'config_service.dart';
import 'log_service.dart';
import 'tray_service.dart';

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

  // Maximum dimensions (4K)
  static const double maxWidth = 3840.0;
  static const double maxHeight = 2160.0;

  /// Validate window state against screen bounds
  Future<WindowState> validateState(WindowState state) async {
    // Clamp size to minimum and maximum (4K resolution)
    final width = max(state.size.width, minWidth).clamp(minWidth, maxWidth);
    final height = max(state.size.height, minHeight).clamp(minHeight, maxHeight);
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

    // Validate position
    var x = state.position!.dx;
    var y = state.position!.dy;

    // Ensure window is at least partially visible
    // X: at least 100px of the window should be visible from the left
    // Y: must be >= 0 (don't go above screen top) and leave room for title bar
    if (x < -width + 100) x = 0;
    if (x > 3800) x = 100; // Don't start too far right on even the largest screens
    if (y < 0) y = 0;
    if (y > 2000) y = 100; // Don't start too far down

    // If position was adjusted significantly, log it
    if (x != state.position!.dx || y != state.position!.dy) {
      LogService().log('Window position adjusted from (${state.position!.dx}, ${state.position!.dy}) to ($x, $y)');
    }

    return WindowState(
      size: size,
      position: Offset(x, y),
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
    // Initialize last known size for resize validation
    _lastKnownSize = await windowManager.getSize();
    // Intercept the close button so we can minimize to tray instead
    if (TrayService().isSupported) {
      await windowManager.setPreventClose(true);
      await windowManager.setMinimizable(false);
    }
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

  /// Save current window state immediately (and flush to disk)
  Future<void> _saveCurrentState() async {
    try {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      _config.setNestedValue(_keyWindowWidth, size.width);
      _config.setNestedValue(_keyWindowHeight, size.height);
      _config.setNestedValue(_keyWindowX, position.dx);
      _config.setNestedValue(_keyWindowY, position.dy);

      // Force immediate save to disk (don't rely on ConfigService debounce)
      await _config.saveNow();

      LogService().log('WindowStateService: Saved window state - ${size.width}x${size.height} at (${position.dx}, ${position.dy})');
    } catch (e) {
      LogService().log('WindowStateService: Error saving window state: $e');
    }
  }

  /// Save maximized state
  void _saveMaximizedState(bool maximized) {
    _isMaximized = maximized;
    _config.setNestedValue(_keyIsMaximized, maximized);
    _config.saveNow(); // Persist immediately
    LogService().log('WindowStateService: Saved maximized state: $maximized');
  }

  // Track last known good size to detect unexpected expansion
  Size? _lastKnownSize;

  // WindowListener callbacks

  @override
  void onWindowResized() async {
    // On Linux, dragging one edge can unexpectedly expand the other dimension.
    // Detect and correct this by comparing to the last known good size.
    try {
      final currentSize = await windowManager.getSize();

      if (_lastKnownSize != null) {
        // Check if width expanded unexpectedly while height was being changed
        // (or vice versa) - this indicates the Linux resize bug
        final widthGrew = currentSize.width > _lastKnownSize!.width + 50;
        final heightGrew = currentSize.height > _lastKnownSize!.height + 50;

        // If both dimensions grew significantly in one resize event, it's suspicious
        if (widthGrew && heightGrew) {
          // Check if size exceeds maximum bounds (4K)
          if (currentSize.width > maxWidth || currentSize.height > maxHeight) {
            LogService().log('WindowStateService: Detected invalid resize, correcting');
            await windowManager.setSize(_lastKnownSize!);
            return;
          }
        }
      }

      _lastKnownSize = currentSize;
    } catch (e) {
      // Ignore errors, just save state
    }

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
  void onWindowClose() async {
    // Save state immediately before closing
    _saveDebounceTimer?.cancel();
    // Only save size/position if not maximized (we want to preserve the unmaximized dimensions)
    if (!_isMaximized) {
      await _saveCurrentState();
    }
    // Try to minimize to tray instead of closing
    final tray = TrayService();
    if (tray.isSupported) {
      await tray.hideToTray();
      // If hideToTray didn't actually hide (setting is off), destroy the window
      if (!tray.isWindowHidden) {
        await windowManager.destroy();
      }
    }
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
