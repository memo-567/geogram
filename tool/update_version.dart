#!/usr/bin/env dart
/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Version sync script - reads version from pubspec.yaml and updates lib/version.dart
 * Run: dart run tool/update_version.dart
 *
 * This is automatically executed by the pre-commit hook to ensure version.dart
 * is always in sync with pubspec.yaml.
 */

import 'dart:io';

void main() {
  final projectRoot = _findProjectRoot();
  if (projectRoot == null) {
    stderr.writeln('Error: Could not find project root (pubspec.yaml not found)');
    exit(1);
  }

  final pubspecFile = File('$projectRoot/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found at $projectRoot');
    exit(1);
  }

  // Read pubspec.yaml and extract version
  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspecContent);

  if (versionMatch == null) {
    stderr.writeln('Error: Could not find version in pubspec.yaml');
    exit(1);
  }

  final fullVersion = versionMatch.group(1)!;

  // Parse version and build number (format: X.Y.Z+N)
  String appVersion;
  String buildNumber;

  if (fullVersion.contains('+')) {
    final parts = fullVersion.split('+');
    appVersion = parts[0];
    buildNumber = parts[1];
  } else {
    appVersion = fullVersion;
    buildNumber = '1';
  }

  // Generate version.dart content
  final versionDartContent = '''/// App version - auto-generated from pubspec.yaml
/// Run: dart run tool/update_version.dart
/// This file is automatically updated by the pre-commit hook
const String appVersion = '$appVersion';
const String appBuildNumber = '$buildNumber';
const String appFullVersion = '\$appVersion+\$appBuildNumber';
''';

  // Write to lib/version.dart
  final versionFile = File('$projectRoot/lib/version.dart');
  final existingContent = versionFile.existsSync() ? versionFile.readAsStringSync() : '';

  if (existingContent == versionDartContent) {
    stdout.writeln('Version already up to date: $appVersion+$buildNumber');
    exit(0);
  }

  versionFile.writeAsStringSync(versionDartContent);
  stdout.writeln('Updated lib/version.dart to version $appVersion+$buildNumber');
  exit(0);
}

/// Find project root by looking for pubspec.yaml
String? _findProjectRoot() {
  var current = Directory.current;

  // First check if we're already in the project root
  if (File('${current.path}/pubspec.yaml').existsSync()) {
    return current.path;
  }

  // Walk up the directory tree
  while (current.path != current.parent.path) {
    if (File('${current.path}/pubspec.yaml').existsSync()) {
      return current.path;
    }
    current = current.parent;
  }

  return null;
}
