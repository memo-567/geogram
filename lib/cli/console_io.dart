/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Platform-agnostic console I/O interface.
 * Allows the same command logic to work with CLI, Flutter UI, Telegram, etc.
 */

/// Platform-agnostic console I/O interface
///
/// Implementations:
/// - [CliConsoleIO] - For CLI mode using stdin/stdout
/// - [BufferConsoleIO] - For Flutter UI and async platforms
abstract class ConsoleIO {
  /// Write a line of text (with newline)
  void writeln([String text = '']);

  /// Write text without newline
  void write(String text);

  /// Read a line of input (async for non-blocking platforms)
  /// Returns null if input is not available or EOF
  Future<String?> readLine();

  /// Read a single byte (for games, raw input)
  /// Returns -1 if not supported or EOF
  Future<int> readByte();

  /// Clear the screen
  void clear();

  /// Set echo mode (for password input, games)
  /// May be no-op on platforms that don't support it
  set echoMode(bool value);

  /// Set line mode (for single-key input)
  /// May be no-op on platforms that don't support it
  set lineMode(bool value);

  /// Whether this I/O supports raw terminal mode (single-key input)
  /// Used to determine if games can run in interactive mode
  bool get supportsRawMode;

  /// Get collected output (for StringBuffer-based implementations)
  /// Returns null for implementations that write directly (CLI)
  String? getOutput();

  /// Clear collected output
  /// No-op for implementations that write directly (CLI)
  void clearOutput();
}
