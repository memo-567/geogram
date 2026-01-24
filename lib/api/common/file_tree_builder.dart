/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * File tree builder utility for sync operations.
 * Builds a recursive file tree structure with file metadata.
 */

import 'dart:io';

/// Builds a recursive file tree structure for sync operations.
///
/// The resulting map uses file/directory names as keys:
/// - Files have `{size: int, mtime: int}` values
/// - Directories end with '/' and contain nested file maps
class FileTreeBuilder {
  /// Build a file tree structure for the given directory path.
  ///
  /// Returns a nested map with file/directory names as keys.
  /// Files have {size: int, mtime: int} values.
  /// Directories end with '/' and contain nested file maps.
  static Future<Map<String, dynamic>> build(String directoryPath) async {
    final tree = <String, dynamic>{};
    final dir = Directory(directoryPath);

    if (!await dir.exists()) return tree;

    await for (final entity in dir.list(recursive: false)) {
      final name = entity.path.split('/').last;

      if (entity is File) {
        final stat = await entity.stat();
        tree[name] = {
          'size': stat.size,
          'mtime': stat.modified.millisecondsSinceEpoch ~/ 1000,
        };
      } else if (entity is Directory) {
        // Recurse into subdirectory
        tree['$name/'] = await build(entity.path);
      }
    }

    return tree;
  }
}
