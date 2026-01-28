/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import '../models/spreadsheet_content.dart';

/// Formula evaluation service
class FormulaService {
  /// Available formula functions with descriptions and syntax hints
  static const formulaFunctions = [
    ('SUM', 'Add values', 'SUM(A1:A10)'),
    ('AVERAGE', 'Calculate mean', 'AVERAGE(A1:A10)'),
    ('COUNT', 'Count numbers', 'COUNT(A1:A10)'),
    ('MIN', 'Minimum value', 'MIN(A1:A10)'),
    ('MAX', 'Maximum value', 'MAX(A1:A10)'),
    ('IF', 'Conditional', 'IF(A1>0, "Yes", "No")'),
    ('ABS', 'Absolute value', 'ABS(A1)'),
    ('ROUND', 'Round number', 'ROUND(A1, 2)'),
    ('LEN', 'String length', 'LEN(A1)'),
    ('CONCAT', 'Join strings', 'CONCAT(A1, B1)'),
  ];

  /// Evaluate a formula in the context of a sheet
  dynamic evaluate(String formula, SpreadsheetSheet sheet) {
    if (!formula.startsWith('=')) {
      return formula;
    }

    try {
      final expr = formula.substring(1).trim().toUpperCase();
      return _evaluateExpression(expr, sheet);
    } catch (e) {
      return '#ERROR!';
    }
  }

  dynamic _evaluateExpression(String expr, SpreadsheetSheet sheet) {
    // Handle function calls
    if (expr.contains('(')) {
      return _evaluateFunction(expr, sheet);
    }

    // Handle cell references
    if (_isCellReference(expr)) {
      return _getCellValue(expr, sheet);
    }

    // Handle numbers
    final num? number = num.tryParse(expr);
    if (number != null) {
      return number;
    }

    // Handle basic arithmetic
    return _evaluateArithmetic(expr, sheet);
  }

  bool _isCellReference(String expr) {
    return RegExp(r'^[A-Z]+\d+$').hasMatch(expr);
  }

  dynamic _getCellValue(String ref, SpreadsheetSheet sheet) {
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref);
    if (match == null) return null;

    final col = SpreadsheetSheet.columnIndex(match.group(1)!);
    final row = int.parse(match.group(2)!) - 1; // Convert to 0-indexed

    final cell = sheet.getCell(row, col);
    if (cell == null) return 0;

    // If cell has a formula, evaluate it
    if (cell.hasFormula) {
      return evaluate(cell.formula!, sheet);
    }

    return cell.value ?? 0;
  }

  dynamic _evaluateFunction(String expr, SpreadsheetSheet sheet) {
    final funcMatch = RegExp(r'^(\w+)\((.*)\)$').firstMatch(expr);
    if (funcMatch == null) return '#NAME?';

    final funcName = funcMatch.group(1)!;
    final argsStr = funcMatch.group(2)!;

    switch (funcName) {
      case 'SUM':
        return _sum(argsStr, sheet);
      case 'AVERAGE':
        return _average(argsStr, sheet);
      case 'COUNT':
        return _count(argsStr, sheet);
      case 'MIN':
        return _min(argsStr, sheet);
      case 'MAX':
        return _max(argsStr, sheet);
      case 'IF':
        return _if(argsStr, sheet);
      case 'ABS':
        return _abs(argsStr, sheet);
      case 'ROUND':
        return _round(argsStr, sheet);
      case 'LEN':
        return _len(argsStr, sheet);
      case 'CONCAT':
        return _concat(argsStr, sheet);
      default:
        return '#NAME?';
    }
  }

  List<dynamic> _parseRange(String range, SpreadsheetSheet sheet) {
    final values = <dynamic>[];

    // Handle range like A1:B5
    if (range.contains(':')) {
      final parts = range.split(':');
      if (parts.length != 2) return values;

      final start = _parseRef(parts[0]);
      final end = _parseRef(parts[1]);
      if (start == null || end == null) return values;

      for (var row = start.$1; row <= end.$1; row++) {
        for (var col = start.$2; col <= end.$2; col++) {
          final val = _getCellValue(
            '${SpreadsheetSheet.columnLetter(col)}${row + 1}',
            sheet,
          );
          if (val != null) values.add(val);
        }
      }
    } else if (_isCellReference(range)) {
      // Single cell reference
      final val = _getCellValue(range, sheet);
      if (val != null) values.add(val);
    } else {
      // Try as number
      final num? number = num.tryParse(range);
      if (number != null) values.add(number);
    }

    return values;
  }

  (int, int)? _parseRef(String ref) {
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref.trim());
    if (match == null) return null;

    final col = SpreadsheetSheet.columnIndex(match.group(1)!);
    final row = int.parse(match.group(2)!) - 1;
    return (row, col);
  }

  List<dynamic> _parseArgs(String argsStr, SpreadsheetSheet sheet) {
    final values = <dynamic>[];
    final args = _splitArgs(argsStr);

    for (final arg in args) {
      values.addAll(_parseRange(arg.trim(), sheet));
    }

    return values;
  }

  /// Split arguments respecting nested parentheses
  List<String> _splitArgs(String argsStr) {
    final args = <String>[];
    var depth = 0;
    var current = StringBuffer();

    for (var i = 0; i < argsStr.length; i++) {
      final char = argsStr[i];
      if (char == '(') {
        depth++;
        current.write(char);
      } else if (char == ')') {
        depth--;
        current.write(char);
      } else if (char == ',' && depth == 0) {
        args.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    if (current.isNotEmpty) {
      args.add(current.toString());
    }

    return args;
  }

  num _sum(String argsStr, SpreadsheetSheet sheet) {
    final values = _parseArgs(argsStr, sheet);
    num sum = 0;
    for (final v in values) {
      if (v is num) sum += v;
    }
    return sum;
  }

  num _average(String argsStr, SpreadsheetSheet sheet) {
    final values = _parseArgs(argsStr, sheet);
    if (values.isEmpty) return 0;

    final nums = values.whereType<num>().toList();
    if (nums.isEmpty) return 0;

    return nums.reduce((a, b) => a + b) / nums.length;
  }

  int _count(String argsStr, SpreadsheetSheet sheet) {
    final values = _parseArgs(argsStr, sheet);
    return values.whereType<num>().length;
  }

  num _min(String argsStr, SpreadsheetSheet sheet) {
    final values = _parseArgs(argsStr, sheet);
    final nums = values.whereType<num>().toList();
    if (nums.isEmpty) return 0;
    return nums.reduce((a, b) => a < b ? a : b);
  }

  num _max(String argsStr, SpreadsheetSheet sheet) {
    final values = _parseArgs(argsStr, sheet);
    final nums = values.whereType<num>().toList();
    if (nums.isEmpty) return 0;
    return nums.reduce((a, b) => a > b ? a : b);
  }

  dynamic _if(String argsStr, SpreadsheetSheet sheet) {
    final args = _splitArgs(argsStr);
    if (args.length < 2) return '#VALUE!';

    final condition = _evaluateCondition(args[0].trim(), sheet);
    if (condition) {
      return _evaluateExpression(args[1].trim(), sheet);
    } else if (args.length > 2) {
      return _evaluateExpression(args[2].trim(), sheet);
    }
    return false;
  }

  bool _evaluateCondition(String expr, SpreadsheetSheet sheet) {
    // Handle comparison operators
    for (final op in ['>=', '<=', '<>', '!=', '=', '>', '<']) {
      final idx = expr.indexOf(op);
      if (idx > 0) {
        final left = _evaluateExpression(
          expr.substring(0, idx).trim(),
          sheet,
        );
        final right = _evaluateExpression(
          expr.substring(idx + op.length).trim(),
          sheet,
        );

        switch (op) {
          case '>=':
            return (left as num) >= (right as num);
          case '<=':
            return (left as num) <= (right as num);
          case '<>':
          case '!=':
            return left != right;
          case '=':
            return left == right;
          case '>':
            return (left as num) > (right as num);
          case '<':
            return (left as num) < (right as num);
        }
      }
    }

    // Truthy check
    final val = _evaluateExpression(expr, sheet);
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) return val.isNotEmpty;
    return false;
  }

  num _abs(String argsStr, SpreadsheetSheet sheet) {
    final args = _parseArgs(argsStr, sheet);
    if (args.isEmpty) return 0;
    final val = args.first;
    if (val is num) return val.abs();
    return 0;
  }

  num _round(String argsStr, SpreadsheetSheet sheet) {
    final args = _splitArgs(argsStr);
    if (args.isEmpty) return 0;

    final val = _evaluateExpression(args[0].trim(), sheet);
    if (val is! num) return 0;

    int decimals = 0;
    if (args.length > 1) {
      final d = _evaluateExpression(args[1].trim(), sheet);
      if (d is num) decimals = d.toInt();
    }

    final factor = _pow(10, decimals);
    return (val * factor).round() / factor;
  }

  num _pow(num base, int exp) {
    num result = 1;
    for (var i = 0; i < exp.abs(); i++) {
      result *= base;
    }
    return exp < 0 ? 1 / result : result;
  }

  int _len(String argsStr, SpreadsheetSheet sheet) {
    final args = _parseArgs(argsStr, sheet);
    if (args.isEmpty) return 0;
    return args.first.toString().length;
  }

  String _concat(String argsStr, SpreadsheetSheet sheet) {
    final args = _parseArgs(argsStr, sheet);
    return args.map((v) => v.toString()).join();
  }

  dynamic _evaluateArithmetic(String expr, SpreadsheetSheet sheet) {
    // Very basic arithmetic: handle + - * / one at a time
    // This is a simplified implementation

    // Handle addition and subtraction (left to right)
    for (var i = expr.length - 1; i >= 0; i--) {
      if (expr[i] == '+' || expr[i] == '-') {
        // Make sure we're not at the start (unary)
        if (i == 0) continue;

        final left = _evaluateExpression(expr.substring(0, i), sheet);
        final right = _evaluateExpression(expr.substring(i + 1), sheet);

        if (left is num && right is num) {
          return expr[i] == '+' ? left + right : left - right;
        }
      }
    }

    // Handle multiplication and division
    for (var i = expr.length - 1; i >= 0; i--) {
      if (expr[i] == '*' || expr[i] == '/') {
        final left = _evaluateExpression(expr.substring(0, i), sheet);
        final right = _evaluateExpression(expr.substring(i + 1), sheet);

        if (left is num && right is num) {
          if (expr[i] == '/') {
            if (right == 0) return '#DIV/0!';
            return left / right;
          }
          return left * right;
        }
      }
    }

    return '#VALUE!';
  }
}
