import 'dart:io';

import 'package:flutter/services.dart';

import '../widgets/file_folder_picker.dart';

/// Service for querying recently modified files via Android MediaStore.
/// Uses the indexed database for fast access even on slow SD cards with many files.
class RecentFilesService {
  static final RecentFilesService _instance = RecentFilesService._internal();
  factory RecentFilesService() => _instance;
  RecentFilesService._internal();

  static const _channel = MethodChannel('dev.geogram/recent_files');

  /// Get a list of recently modified files from MediaStore.
  /// Returns an empty list on non-Android platforms.
  Future<List<FileSystemItem>> getRecentFiles({int limit = 100}) async {
    if (!Platform.isAndroid) return [];

    try {
      final result = await _channel.invokeMethod('getRecentFiles', {'limit': limit});
      if (result == null) return [];

      return (result as List).map((item) {
        final map = item as Map;
        return FileSystemItem(
          path: map['path'] as String,
          name: map['name'] as String? ?? '',
          isDirectory: false,
          size: (map['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num?)?.toInt() ?? 0,
          ),
          type: FileSystemEntityType.file,
        );
      }).toList();
    } catch (e) {
      // Method channel not available or error - return empty list
      return [];
    }
  }
}
