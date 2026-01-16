/*
 * NOSTR storage paths for pure Dart/CLI.
 */

import 'dart:io';
import 'package:path/path.dart' as path;

import '../cli/pure_storage_config.dart';

class NostrStoragePaths {
  static String baseDir({String? overrideBase}) {
    if (overrideBase != null && overrideBase.isNotEmpty) {
      return overrideBase;
    }
    final workingDir = Directory.current;
    final looksLikeRepo = File(path.join(workingDir.path, 'pubspec.yaml')).existsSync() &&
        Directory(path.join(workingDir.path, 'lib')).existsSync();
    if (looksLikeRepo) {
      return path.join(workingDir.path, 'nostr');
    }
    final storage = PureStorageConfig();
    if (storage.isInitialized) {
      return path.join(storage.baseDir, 'nostr');
    }
    return path.join(Directory.current.path, 'nostr');
  }

  static String relayDbPath({String? overrideBase}) {
    return path.join(baseDir(overrideBase: overrideBase), 'relay.sqlite3');
  }

  static String blossomDbPath({String? overrideBase}) {
    return path.join(baseDir(overrideBase: overrideBase), 'blossom.sqlite3');
  }

  static String blossomDir({String? overrideBase}) {
    return path.join(baseDir(overrideBase: overrideBase), 'blossom');
  }
}
