/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/services.dart';
import 'debug_controller.dart';
import 'log_service.dart';

/// Service to handle USB device attachment events from Android
/// Listens to the native MethodChannel and triggers navigation
/// to Flasher Monitor tab when an ESP32 device is connected
class UsbAttachmentService {
  static final UsbAttachmentService _instance = UsbAttachmentService._internal();
  factory UsbAttachmentService() => _instance;
  UsbAttachmentService._internal();

  static const _channel = MethodChannel('dev.geogram/usb_attach');
  bool _initialized = false;

  /// Initialize the service and start listening for USB events
  void initialize() {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler(_handleMethodCall);
    _initialized = true;
    LogService().log('[USB] UsbAttachmentService initialized');
  }

  /// Handle method calls from native code
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onUsbDeviceAttached':
        final args = call.arguments as Map<dynamic, dynamic>;
        final deviceName = args['deviceName'] as String?;
        final vid = args['vid'] as int?;
        final pid = args['pid'] as int?;
        final isEsp32 = args['isEsp32'] as bool? ?? false;

        LogService().log(
          '[USB] Device attached: $deviceName (VID=$vid, PID=$pid, isEsp32=$isEsp32)',
        );

        // Only auto-navigate for confirmed ESP32 devices
        if (isEsp32) {
          LogService().log('[USB] ESP32 detected, opening Flasher Monitor');
          DebugController().triggerOpenFlasherMonitor(devicePath: deviceName);
        } else {
          LogService().log('[USB] Non-ESP32 device, skipping auto-navigation');
        }
        break;

      default:
        LogService().log('[USB] Unknown method: ${call.method}');
    }
  }

  /// Dispose the service
  void dispose() {
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }
}
