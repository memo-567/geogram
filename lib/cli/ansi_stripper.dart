/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * ANSI escape code stripper utility.
 */

/// Utility to strip ANSI escape codes from text.
///
/// Used to clean output for platforms that don't support ANSI
/// (Flutter UI, chat messengers, plain text).
class AnsiStripper {
  /// Pattern matching ANSI escape sequences:
  /// - CSI sequences: ESC [ ... letter (colors, cursor, etc.)
  /// - OSC sequences: ESC ] ... BEL/ST (title, hyperlinks)
  static final _ansiPattern = RegExp(
    r'\x1B'        // ESC character
    r'(?:'
      r'\[[0-9;]*[A-Za-z]'  // CSI: ESC [ params letter
      r'|'
      r'\][^\x07]*\x07'     // OSC: ESC ] ... BEL
    r')',
  );

  /// Strip all ANSI escape codes from text.
  static String strip(String text) => text.replaceAll(_ansiPattern, '');

  /// Check if text contains ANSI escape codes.
  static bool hasAnsi(String text) => _ansiPattern.hasMatch(text);
}
