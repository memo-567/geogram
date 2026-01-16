/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * CLI implementation of ConsoleIO using stdin/stdout.
 * For use in command-line mode.
 */

import 'dart:io';

import 'console_io.dart';

/// CLI implementation using stdin/stdout
class CliConsoleIO implements ConsoleIO {
  @override
  void writeln([String text = '']) => stdout.writeln(text);

  @override
  void write(String text) => stdout.write(text);

  @override
  Future<String?> readLine() async => stdin.readLineSync();

  @override
  Future<int> readByte() async => stdin.readByteSync();

  @override
  void clear() => stdout.write('\x1B[2J\x1B[H');

  @override
  set echoMode(bool value) => stdin.echoMode = value;

  @override
  set lineMode(bool value) => stdin.lineMode = value;

  @override
  bool get supportsRawMode => true;

  @override
  String? getOutput() => null; // CLI writes directly, no buffer

  @override
  void clearOutput() {} // No-op for CLI
}
