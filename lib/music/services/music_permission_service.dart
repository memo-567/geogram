/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Service for handling music/audio storage permissions on Android
class MusicPermissionService {
  /// Request audio/storage permissions
  /// Returns true if granted, false otherwise
  ///
  /// On Android 13+ (API 33), requests READ_MEDIA_AUDIO permission.
  /// On older Android versions, requests READ_EXTERNAL_STORAGE.
  /// On non-Android platforms, always returns true.
  static Future<bool> requestAudioPermission() async {
    if (!Platform.isAndroid) return true;

    // Try audio permission first (Android 13+)
    // If not applicable, fall back to storage permission
    var status = await Permission.audio.status;

    if (status.isGranted) return true;

    // If audio permission exists (Android 13+), request it
    if (!status.isPermanentlyDenied) {
      status = await Permission.audio.request();
      if (status.isGranted) return true;
    }

    // Fall back to storage permission for older Android versions
    status = await Permission.storage.status;
    if (status.isGranted) return true;

    if (!status.isPermanentlyDenied) {
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }

  /// Check if audio/storage permissions are granted
  static Future<bool> hasAudioPermission() async {
    if (!Platform.isAndroid) return true;

    // Check both permissions - one will be granted depending on Android version
    final audioGranted = await Permission.audio.isGranted;
    final storageGranted = await Permission.storage.isGranted;

    return audioGranted || storageGranted;
  }

  /// Check if permission is permanently denied
  static Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    final audioDenied = await Permission.audio.isPermanentlyDenied;
    final storageDenied = await Permission.storage.isPermanentlyDenied;

    // If either is permanently denied, user needs to go to settings
    return audioDenied || storageDenied;
  }

  /// Open app settings (for when permission is permanently denied)
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
