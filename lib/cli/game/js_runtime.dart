import 'dart:math';

/// JavaScript runtime wrapper for game scripting
/// Uses ensemble_ts_interpreter for JS execution
class JsRuntime {
  /// Execute JavaScript code with entity context
  /// Returns the modified context including 'output' variable
  Map<String, dynamic> execute(
    String code, {
    required Map<String, dynamic> entityA,
    required Map<String, dynamic> entityB,
  }) {
    // Create context with entities
    final context = <String, dynamic>{
      'A': Map<String, dynamic>.from(entityA),
      'B': Map<String, dynamic>.from(entityB),
      'AttackPowerA': entityA['Attack'] ?? 0,
      'DefendPowerA': entityA['Defense'] ?? 0,
      'AttackPowerB': entityB['Attack'] ?? 0,
      'DefendPowerB': entityB['Defense'] ?? 0,
      'output': 'continue',
    };

    try {
      // Simple JavaScript interpreter for basic game logic
      // Handles the common patterns used in game scripts
      _executeSimpleJs(code, context);
    } catch (e) {
      // On error, default to continue
      context['output'] = 'continue';
    }

    return context;
  }

  /// Simple JS interpreter for basic game operations
  /// Supports: variable assignment, Math functions, conditionals
  void _executeSimpleJs(String code, Map<String, dynamic> context) {
    // Join lines and process as blocks for if-else handling
    final fullCode = code.replaceAll('\r\n', '\n');
    _executeBlock(fullCode, context);
  }

  void _executeBlock(String code, Map<String, dynamic> context) {
    var remaining = code.trim();

    while (remaining.isNotEmpty) {
      remaining = remaining.trim();
      if (remaining.isEmpty) break;

      // Skip comments
      if (remaining.startsWith('//')) {
        final newlineIndex = remaining.indexOf('\n');
        if (newlineIndex == -1) break;
        remaining = remaining.substring(newlineIndex + 1);
        continue;
      }

      // Handle if statement
      if (remaining.startsWith('if ') || remaining.startsWith('if(')) {
        remaining = _handleIfStatement(remaining, context);
        continue;
      }

      // Find end of current statement (semicolon or newline)
      var endIndex = remaining.indexOf(';');
      final newlineIndex = remaining.indexOf('\n');

      if (endIndex == -1 && newlineIndex == -1) {
        // Last statement
        _executeLine(remaining, context);
        break;
      }

      if (endIndex == -1 || (newlineIndex != -1 && newlineIndex < endIndex)) {
        endIndex = newlineIndex;
      }

      final statement = remaining.substring(0, endIndex).trim();
      remaining = remaining.substring(endIndex + 1);

      if (statement.isNotEmpty) {
        _executeLine(statement, context);
      }
    }
  }

  void _executeLine(String line, Map<String, dynamic> context) {
    var processedLine = line.trim();

    // Skip empty lines and comments
    if (processedLine.isEmpty || processedLine.startsWith('//')) return;

    // Remove trailing semicolon
    if (processedLine.endsWith(';')) {
      processedLine = processedLine.substring(0, processedLine.length - 1).trim();
    }

    // Handle var declarations
    if (processedLine.startsWith('var ')) {
      processedLine = processedLine.substring(4).trim();
    }

    // Handle assignment (but not == or <= or >=)
    final eqIndex = processedLine.indexOf('=');
    if (eqIndex > 0) {
      final beforeEq = processedLine.substring(eqIndex - 1, eqIndex);
      final afterEq = eqIndex + 1 < processedLine.length ? processedLine.substring(eqIndex + 1, eqIndex + 2) : '';
      if (beforeEq != '=' && beforeEq != '!' && beforeEq != '<' && beforeEq != '>' && afterEq != '=') {
        _handleAssignment(processedLine, context);
      }
    }
  }

  void _handleAssignment(String line, Map<String, dynamic> context) {
    // Split on first = that's not part of == or <=  or >=
    var eqIndex = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '=') {
        final before = i > 0 ? line[i - 1] : ' ';
        final after = i + 1 < line.length ? line[i + 1] : ' ';
        if (before != '=' && before != '!' && before != '<' && before != '>' && after != '=') {
          eqIndex = i;
          break;
        }
      }
    }

    if (eqIndex == -1) return;

    final leftSide = line.substring(0, eqIndex).trim();
    final rightSide = line.substring(eqIndex + 1).trim();

    // Evaluate right side
    final value = _evaluate(rightSide, context);

    // Assign to left side
    _assign(leftSide, value, context);
  }

  /// Handle if-else statement, returns remaining code after the if-else block
  String _handleIfStatement(String code, Map<String, dynamic> context) {
    // Parse: if (condition) { ... } else { ... }
    var remaining = code;

    // Extract condition
    final condStart = remaining.indexOf('(');
    if (condStart == -1) return remaining;

    var depth = 0;
    var condEnd = -1;
    for (var i = condStart; i < remaining.length; i++) {
      if (remaining[i] == '(') depth++;
      if (remaining[i] == ')') depth--;
      if (depth == 0) {
        condEnd = i;
        break;
      }
    }
    if (condEnd == -1) return remaining;

    final condition = remaining.substring(condStart + 1, condEnd).trim();
    remaining = remaining.substring(condEnd + 1).trim();

    // Extract if body
    final ifBody = _extractBlock(remaining);
    remaining = remaining.substring(ifBody.length).trim();

    // Check for else
    String? elseBody;
    if (remaining.startsWith('else')) {
      remaining = remaining.substring(4).trim();
      elseBody = _extractBlock(remaining);
      remaining = remaining.substring(elseBody.length).trim();
    }

    // Evaluate condition and execute appropriate block
    final condResult = _evaluateCondition(condition, context);
    if (condResult) {
      _executeBlock(_unwrapBlock(ifBody), context);
    } else if (elseBody != null) {
      _executeBlock(_unwrapBlock(elseBody), context);
    }

    return remaining;
  }

  /// Extract a block of code (either { ... } or single statement)
  String _extractBlock(String code) {
    final trimmed = code.trim();
    if (trimmed.startsWith('{')) {
      var depth = 0;
      for (var i = 0; i < trimmed.length; i++) {
        if (trimmed[i] == '{') depth++;
        if (trimmed[i] == '}') depth--;
        if (depth == 0) {
          return trimmed.substring(0, i + 1);
        }
      }
    }
    // Single statement - find semicolon or newline
    final semiIndex = trimmed.indexOf(';');
    final newlineIndex = trimmed.indexOf('\n');
    if (semiIndex == -1 && newlineIndex == -1) return trimmed;
    if (semiIndex == -1) return trimmed.substring(0, newlineIndex);
    if (newlineIndex == -1) return trimmed.substring(0, semiIndex + 1);
    return trimmed.substring(0, semiIndex < newlineIndex ? semiIndex + 1 : newlineIndex);
  }

  /// Remove { } braces from a block
  String _unwrapBlock(String block) {
    final trimmed = block.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  dynamic _evaluate(String expr, Map<String, dynamic> context) {
    var cleanExpr = expr.trim();

    // Strip outer parentheses
    while (cleanExpr.startsWith('(') && cleanExpr.endsWith(')')) {
      // Make sure these are matching outer parens
      var depth = 0;
      var isOuter = true;
      for (var i = 0; i < cleanExpr.length - 1; i++) {
        if (cleanExpr[i] == '(') depth++;
        if (cleanExpr[i] == ')') depth--;
        if (depth == 0 && i > 0) {
          isOuter = false;
          break;
        }
      }
      if (isOuter) {
        cleanExpr = cleanExpr.substring(1, cleanExpr.length - 1).trim();
      } else {
        break;
      }
    }

    // Handle ternary operator
    if (cleanExpr.contains('?') && cleanExpr.contains(':')) {
      return _evaluateTernary(cleanExpr, context);
    }

    // Handle string literals
    if ((cleanExpr.startsWith("'") && cleanExpr.endsWith("'")) ||
        (cleanExpr.startsWith('"') && cleanExpr.endsWith('"'))) {
      return cleanExpr.substring(1, cleanExpr.length - 1);
    }

    // Handle numbers
    final numValue = num.tryParse(cleanExpr);
    if (numValue != null) {
      return numValue;
    }

    // Handle Math functions
    if (cleanExpr.startsWith('Math.')) {
      return _evaluateMath(cleanExpr, context);
    }

    // Handle arithmetic expressions FIRST (they may contain indexed access as operands)
    // Check if there's an operator outside of brackets
    if (_hasArithmeticOperator(cleanExpr)) {
      return _evaluateArithmetic(cleanExpr, context);
    }

    // Handle variable access: A['Health'] or simple variables
    if (cleanExpr.contains('[')) {
      return _getIndexedValue(cleanExpr, context);
    }

    // Simple variable lookup
    return context[cleanExpr] ?? 0;
  }

  dynamic _evaluateTernary(String expr, Map<String, dynamic> context) {
    final questionIndex = expr.indexOf('?');
    final colonIndex = expr.lastIndexOf(':');

    if (questionIndex == -1 || colonIndex == -1) return 'continue';

    final condition = expr.substring(0, questionIndex).trim();
    final trueValue = expr.substring(questionIndex + 1, colonIndex).trim();
    final falseValue = expr.substring(colonIndex + 1).trim();

    final conditionResult = _evaluateCondition(condition, context);
    return conditionResult ? _evaluate(trueValue, context) : _evaluate(falseValue, context);
  }

  bool _evaluateCondition(String condition, Map<String, dynamic> context) {
    // Handle comparison operators
    if (condition.contains('<=')) {
      final parts = condition.split('<=');
      final left = _evaluate(parts[0].trim(), context);
      final right = _evaluate(parts[1].trim(), context);
      return (left as num) <= (right as num);
    }
    if (condition.contains('>=')) {
      final parts = condition.split('>=');
      final left = _evaluate(parts[0].trim(), context);
      final right = _evaluate(parts[1].trim(), context);
      return (left as num) >= (right as num);
    }
    if (condition.contains('<')) {
      final parts = condition.split('<');
      final left = _evaluate(parts[0].trim(), context);
      final right = _evaluate(parts[1].trim(), context);
      return (left as num) < (right as num);
    }
    if (condition.contains('>')) {
      final parts = condition.split('>');
      final left = _evaluate(parts[0].trim(), context);
      final right = _evaluate(parts[1].trim(), context);
      return (left as num) > (right as num);
    }
    if (condition.contains('==')) {
      final parts = condition.split('==');
      final left = _evaluate(parts[0].trim(), context);
      final right = _evaluate(parts[1].trim(), context);
      return left == right;
    }

    // Truthy check
    final value = _evaluate(condition, context);
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value != null;
  }

  num _evaluateMath(String expr, Map<String, dynamic> context) {
    // Handle Math.max(a, b)
    if (expr.startsWith('Math.max(')) {
      final args = _extractFunctionArgs(expr.substring(9));
      final values = args.map((a) => _evaluate(a, context) as num).toList();
      return values.reduce((a, b) => a > b ? a : b);
    }
    // Handle Math.min(a, b)
    if (expr.startsWith('Math.min(')) {
      final args = _extractFunctionArgs(expr.substring(9));
      final values = args.map((a) => _evaluate(a, context) as num).toList();
      return values.reduce((a, b) => a < b ? a : b);
    }
    // Handle Math.floor(n)
    if (expr.startsWith('Math.floor(')) {
      final args = _extractFunctionArgs(expr.substring(11));
      final value = _evaluate(args[0], context) as num;
      return value.floor();
    }
    // Handle Math.random()
    if (expr.startsWith('Math.random()')) {
      return Random().nextDouble();
    }
    return 0;
  }

  List<String> _extractFunctionArgs(String argsWithParen) {
    // Remove closing parenthesis
    var args = argsWithParen;
    if (args.endsWith(')')) {
      args = args.substring(0, args.length - 1);
    }

    // Split by comma, respecting nested parentheses
    final result = <String>[];
    var depth = 0;
    var current = StringBuffer();

    for (var i = 0; i < args.length; i++) {
      final char = args[i];
      if (char == '(') {
        depth++;
        current.write(char);
      } else if (char == ')') {
        depth--;
        current.write(char);
      } else if (char == ',' && depth == 0) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    if (current.isNotEmpty) {
      result.add(current.toString().trim());
    }

    return result;
  }

  dynamic _getIndexedValue(String expr, Map<String, dynamic> context) {
    // Parse A['Health'] style access
    final match = RegExp(r"(\w+)\['(\w+)'\]").firstMatch(expr);
    if (match != null) {
      final objName = match.group(1)!;
      final key = match.group(2)!;
      final obj = context[objName];
      if (obj is Map) {
        return obj[key] ?? 0;
      }
    }
    return 0;
  }

  num _evaluateArithmetic(String expr, Map<String, dynamic> context) {
    // Split respecting parentheses - find lowest precedence operator outside parens
    // Precedence: +/- (lowest), then */  (higher)

    // First try +/- (left to right, outside parentheses)
    var opIndex = _findOperatorOutsideParens(expr, ['+', '-']);
    if (opIndex != -1) {
      final op = expr[opIndex];
      final left = expr.substring(0, opIndex).trim();
      final right = expr.substring(opIndex + 1).trim();
      final leftVal = _evaluate(left, context) as num;
      final rightVal = _evaluate(right, context) as num;
      return op == '+' ? leftVal + rightVal : leftVal - rightVal;
    }

    // Then try */ (left to right, outside parentheses)
    opIndex = _findOperatorOutsideParens(expr, ['*', '/']);
    if (opIndex != -1) {
      final op = expr[opIndex];
      final left = expr.substring(0, opIndex).trim();
      final right = expr.substring(opIndex + 1).trim();
      final leftVal = _evaluate(left, context) as num;
      final rightVal = _evaluate(right, context) as num;
      if (op == '*') return leftVal * rightVal;
      if (rightVal != 0) return leftVal / rightVal;
      return 0;
    }

    return _evaluate(expr, context) as num;
  }

  /// Check if expression has an arithmetic operator outside brackets/parens
  bool _hasArithmeticOperator(String expr) {
    return _findOperatorOutsideParens(expr, ['+', '-']) != -1 ||
           _findOperatorOutsideParens(expr, ['*', '/']) != -1;
  }

  /// Find the rightmost operator from the list that's outside parentheses
  int _findOperatorOutsideParens(String expr, List<String> operators) {
    var depth = 0;
    var bracketDepth = 0;
    // Scan right to left for left-to-right associativity
    for (var i = expr.length - 1; i >= 0; i--) {
      final char = expr[i];
      if (char == ')') depth++;
      if (char == '(') depth--;
      if (char == ']') bracketDepth++;
      if (char == '[') bracketDepth--;

      if (depth == 0 && bracketDepth == 0 && operators.contains(char)) {
        // Make sure it's not part of a different operator
        if (i > 0) {
          final prevChar = expr[i - 1];
          // Skip if previous char is also an operator (like <=, >=, ==)
          if (prevChar == '<' || prevChar == '>' || prevChar == '=' || prevChar == '!') {
            continue;
          }
        }
        return i;
      }
    }
    return -1;
  }

  void _assign(String target, dynamic value, Map<String, dynamic> context) {
    // Handle A['Health'] style assignment
    final match = RegExp(r"(\w+)\['(\w+)'\]").firstMatch(target);
    if (match != null) {
      final objName = match.group(1)!;
      final key = match.group(2)!;
      final obj = context[objName];
      if (obj is Map<String, dynamic>) {
        obj[key] = value is num ? value.toInt() : value;
      }
      return;
    }

    // Simple variable assignment
    context[target] = value;
  }
}
