import 'dart:io';

/// Text formatting utilities for game display
class StoryUtils {
  /// Word wrap text to specified width
  static List<String> wrapText(String text, int width) {
    final words = text.split(' ');
    final lines = <String>[];
    var currentLine = StringBuffer();

    for (final word in words) {
      if (currentLine.length + word.length + 1 > width) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.toString());
        }
        currentLine = StringBuffer(word);
      } else {
        if (currentLine.isNotEmpty) currentLine.write(' ');
        currentLine.write(word);
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine.toString());
    }

    return lines.isEmpty ? [''] : lines;
  }

  /// Generate ASCII art title box
  static List<String> generateTitleBox(String text, {int padding = 2}) {
    final paddedText = ' ' * padding + text + ' ' * padding;
    final width = paddedText.length + 2;

    return [
      '\x1B[1;36m' + '╔' + '═' * width + '╗' + '\x1B[0m',
      '\x1B[1;36m' + '║ $paddedText ║' + '\x1B[0m',
      '\x1B[1;36m' + '╚' + '═' * width + '╝' + '\x1B[0m',
    ];
  }

  /// Display two ASCII art blocks side by side
  static void listSideBySide(List<String> left, List<String> right, {int gap = 4}) {
    final maxLeftWidth = left.isEmpty ? 0 : left.map((l) => l.length).reduce((a, b) => a > b ? a : b);
    final maxLines = left.length > right.length ? left.length : right.length;

    for (var i = 0; i < maxLines; i++) {
      final l = i < left.length ? left[i].padRight(maxLeftWidth) : ' ' * maxLeftWidth;
      final r = i < right.length ? right[i] : '';
      stdout.writeln('  $l${' ' * gap}$r');
    }
  }

  /// Generate health bar
  static String healthBar(int current, int max, {int width = 20}) {
    final percent = max > 0 ? (current / max * width).round().clamp(0, width) : 0;
    final filled = '#' * percent;
    final empty = '-' * (width - percent);

    // Color based on health percentage
    final percentage = max > 0 ? current / max : 0;
    String color;
    if (percentage > 0.6) {
      color = '\x1B[32m'; // Green
    } else if (percentage > 0.3) {
      color = '\x1B[33m'; // Yellow
    } else {
      color = '\x1B[31m'; // Red
    }

    return '[$color$filled\x1B[90m$empty\x1B[0m] $current/$max';
  }

  /// Print text with typewriter effect
  static Future<void> typewriterPrint(String text, {Duration charDelay = const Duration(milliseconds: 20)}) async {
    for (var i = 0; i < text.length; i++) {
      stdout.write(text[i]);
      await Future.delayed(charDelay);
    }
    stdout.writeln();
  }

  /// Clear screen
  static void clearScreen() {
    stdout.write('\x1B[2J\x1B[H');
  }

  /// Move cursor to position
  static void moveCursor(int row, int col) {
    stdout.write('\x1B[$row;${col}H');
  }

  /// Print colored text
  static void printColored(String text, String colorCode) {
    stdout.writeln('$colorCode$text\x1B[0m');
  }

  /// ANSI color codes
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  static const String reset = '\x1B[0m';

  /// Print a horizontal line
  static void printLine({int width = 60, String char = '-'}) {
    stdout.writeln(char * width);
  }

  /// Print a boxed message
  static void printBox(String message, {int width = 60}) {
    final lines = wrapText(message, width - 4);
    stdout.writeln('┌${'-' * (width - 2)}┐');
    for (final line in lines) {
      stdout.writeln('│ ${line.padRight(width - 4)} │');
    }
    stdout.writeln('└${'-' * (width - 2)}┘');
  }

  /// Parse attribute modifier like "+10" or "-5"
  static int parseModifier(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      return int.tryParse(trimmed.substring(1)) ?? 0;
    } else if (trimmed.startsWith('-')) {
      return -(int.tryParse(trimmed.substring(1)) ?? 0);
    }
    return int.tryParse(trimmed) ?? 0;
  }

  /// Extract text between markers
  static String? extractBetween(String text, String start, String end) {
    final startIndex = text.indexOf(start);
    if (startIndex == -1) return null;

    final contentStart = startIndex + start.length;
    final endIndex = text.indexOf(end, contentStart);
    if (endIndex == -1) return null;

    return text.substring(contentStart, endIndex);
  }
}
