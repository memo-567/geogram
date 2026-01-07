#!/usr/bin/env dart
// Standalone CLI entry point for geogram
// This is pure Dart CLI mode with no Flutter dependencies
//
// Build: dart compile exe bin/cli.dart -o geogram-cli
// Run: ./geogram-cli

import '../lib/cli/pure_console.dart';

Future<void> main(List<String> args) async {
  // Run pure Dart CLI mode
  await runPureCliMode(args);
}
