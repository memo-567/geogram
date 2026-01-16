/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Buffer-based ConsoleIO implementation for Flutter UI and async platforms.
 * Collects output in a StringBuffer for retrieval by the UI.
 */

import 'ansi_stripper.dart';
import 'console_io.dart';

/// Buffer-based implementation for Flutter UI and async platforms
///
/// Output is collected in a StringBuffer and can be retrieved via [getOutput].
/// This allows the same command logic to work with UI-based consoles.
/// ANSI escape codes are automatically stripped for clean display.
class BufferConsoleIO implements ConsoleIO {
  final StringBuffer _output = StringBuffer();

  /// Optional callback for reading input
  /// Set this to enable interactive input from the UI
  Future<String?> Function()? readLineCallback;

  BufferConsoleIO({this.readLineCallback});

  @override
  void writeln([String text = '']) => _output.writeln(AnsiStripper.strip(text));

  @override
  void write(String text) => _output.write(AnsiStripper.strip(text));

  @override
  Future<String?> readLine() async => readLineCallback?.call();

  @override
  Future<int> readByte() async => -1; // Not supported in buffer mode

  @override
  void clear() {
    _output.clear();
    // Signal clear screen with escape code
    _output.write('\x1B[CLEAR]');
  }

  @override
  set echoMode(bool value) {} // Not applicable in buffer mode

  @override
  set lineMode(bool value) {} // Not applicable in buffer mode

  @override
  bool get supportsRawMode => false;

  @override
  String? getOutput() => _output.toString();

  @override
  void clearOutput() => _output.clear();
}
