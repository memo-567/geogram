/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'log_service.dart';

/// Service for launching files and folders in the system's default application.
///
/// Provides cross-platform support for:
/// - Opening folders in the system file browser
/// - Opening files with their associated application
///
/// Supported platforms: Android, iOS, Linux, macOS, Windows
class FileLauncherService {
  static final FileLauncherService _instance = FileLauncherService._internal();
  factory FileLauncherService() => _instance;
  FileLauncherService._internal();

  /// Open a folder in the system's default file browser.
  ///
  /// Returns true if the folder was opened successfully, false otherwise.
  ///
  /// Platform behavior:
  /// - **Linux**: Uses xdg-open
  /// - **macOS**: Uses open command
  /// - **Windows**: Uses explorer
  /// - **Android**: Uses ACTION_VIEW intent via url_launcher
  /// - **iOS**: Uses url_launcher (limited support - opens Files app if available)
  /// - **Web**: Not supported, returns false
  Future<bool> openFolder(String path) async {
    if (kIsWeb) {
      LogService().log('FileLauncherService: Cannot open folder on web platform');
      return false;
    }

    try {
      // First try using url_launcher with file:// URI
      final uri = Uri.parse('file://$path');
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);
        if (launched) return true;
      }

      // Fallback to platform-specific commands
      return await _openFolderPlatformSpecific(path);
    } catch (e) {
      LogService().log('FileLauncherService: Error opening folder: $e');
      return false;
    }
  }

  /// Open a file with its associated application.
  ///
  /// Returns true if the file was opened successfully, false otherwise.
  Future<bool> openFile(String path) async {
    if (kIsWeb) {
      LogService().log('FileLauncherService: Cannot open file on web platform');
      return false;
    }

    try {
      final uri = Uri.parse('file://$path');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }

      // Fallback to platform-specific commands
      return await _openFilePlatformSpecific(path);
    } catch (e) {
      LogService().log('FileLauncherService: Error opening file: $e');
      return false;
    }
  }

  /// Open a URL in the default browser.
  ///
  /// Returns true if the URL was opened successfully, false otherwise.
  Future<bool> openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      LogService().log('FileLauncherService: Error opening URL: $e');
      return false;
    }
  }

  /// Platform-specific folder opening
  Future<bool> _openFolderPlatformSpecific(String path) async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [path]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final result = await Process.run('open', [path]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('explorer', [path]);
        // Explorer returns 1 even on success sometimes
        return result.exitCode == 0 || result.exitCode == 1;
      } else if (Platform.isAndroid) {
        // On Android, use content:// URI via url_launcher
        // The file:// scheme works for most file managers
        final uri = Uri.parse('file://$path');
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (Platform.isIOS) {
        // iOS has limited file system access
        // Try to open via shareable URL if available
        final uri = Uri.parse('shareddocuments://$path');
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
        // Fallback to file:// which may work with Files app
        final fileUri = Uri.parse('file://$path');
        return await launchUrl(fileUri);
      }
      return false;
    } catch (e) {
      LogService().log('FileLauncherService: Platform-specific open failed: $e');
      return false;
    }
  }

  /// Platform-specific file opening
  Future<bool> _openFilePlatformSpecific(String path) async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [path]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final result = await Process.run('open', [path]);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('start', ['', path], runInShell: true);
        return result.exitCode == 0;
      } else if (Platform.isAndroid || Platform.isIOS) {
        final uri = Uri.parse('file://$path');
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      LogService().log('FileLauncherService: Platform-specific file open failed: $e');
      return false;
    }
  }

  /// Check if the current platform supports opening folders.
  bool get canOpenFolders {
    if (kIsWeb) return false;
    return Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isIOS;
  }

  /// Check if the current platform supports opening files.
  bool get canOpenFiles {
    if (kIsWeb) return false;
    return Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isIOS;
  }
}
