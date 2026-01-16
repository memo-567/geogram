/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Console terminal page - Traditional terminal interface.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cli_console_controller.dart';
import '../services/i18n_service.dart';

/// Traditional terminal page with inline input
class ConsoleTerminalPage extends StatefulWidget {
  const ConsoleTerminalPage({super.key});

  @override
  State<ConsoleTerminalPage> createState() => _ConsoleTerminalPageState();
}

class _ConsoleTerminalPageState extends State<ConsoleTerminalPage> {
  final I18nService _i18n = I18nService();
  final CliConsoleController _controller = CliConsoleController();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  /// Terminal output as styled spans
  final List<_TerminalSpan> _spans = [];

  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  bool _isProcessing = false;

  // Colors (set in build)
  late Color _textColor;
  late Color _promptColor;

  // Monospace font stack for good Unicode/ASCII art support
  static const _fontFamily = 'DejaVu Sans Mono';
  static const _fontFamilyFallback = ['Ubuntu Mono', 'Liberation Mono', 'monospace'];

  @override
  void initState() {
    super.initState();
    // Initialize controller and show banner after first build
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAndShowBanner());
  }

  Future<void> _initializeAndShowBanner() async {
    await _controller.initialize();

    // Set up game output callback
    _controller.onGameOutput = (output) {
      if (mounted) {
        setState(() {
          // Handle clear screen marker from game
          if (output.contains('\x1B[CLEAR]')) {
            _spans.clear();
            output = output.replaceAll('\x1B[CLEAR]', '');
          }
          if (output.isNotEmpty) {
            _spans.add(_TerminalSpan(output, isOutput: true));
          }
        });
        _scrollToBottom();
      }
    };

    _showBanner();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showBanner() {
    final banner = _controller.getBanner();
    setState(() {
      _spans.add(_TerminalSpan(banner, isOutput: true));
    });
  }

  Future<void> _submitCommand(String input) async {
    final prompt = _controller.getPrompt();

    // Add command line to output (prompt in cyan, command in green)
    setState(() {
      _spans.add(_TerminalSpan(prompt, isPrompt: true));
      _spans.add(_TerminalSpan('$input\n', isOutput: true));
      _isProcessing = true;
    });

    _inputController.clear();
    _scrollToBottom();

    // Handle empty input - just show new prompt
    if (input.trim().isEmpty) {
      setState(() => _isProcessing = false);
      _focusNode.requestFocus();
      return;
    }

    // Add command to history (avoid duplicates, skip empty)
    if (input.trim().isNotEmpty && (_commandHistory.isEmpty || _commandHistory.last != input)) {
      _commandHistory.add(input);
    }
    _historyIndex = _commandHistory.length;

    // Process command
    final output = await _controller.processCommand(input);

    // Check for clear command
    if (output.contains('\x1B[CLEAR]')) {
      setState(() {
        _spans.clear();
        _isProcessing = false;
      });
      _focusNode.requestFocus();
      return;
    }

    // Add output (trimmed to avoid double newlines)
    if (output.isNotEmpty) {
      setState(() {
        var trimmed = output.trimRight();
        _spans.add(_TerminalSpan('$trimmed\n', isOutput: true));
        _isProcessing = false;
      });
    } else {
      setState(() => _isProcessing = false);
    }

    _scrollToBottom();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Handle TAB completion using shared ConsoleCompleter
  void _handleTabCompletion() {
    final input = _inputController.text;
    final currentPath = _controller.currentPath;

    // Use shared completer
    final completer = _controller.completer;
    final result = completer.complete(input, currentPath);

    if (result.exactMatch && result.completedText != null) {
      // Single match - complete it
      _inputController.text = result.completedText!;
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    } else if (result.candidates.isNotEmpty) {
      // Multiple matches - show them
      final displayLines = completer.formatCandidatesForDisplay(result.candidates);
      setState(() {
        _spans.add(_TerminalSpan(_controller.getPrompt(), isPrompt: true));
        _spans.add(_TerminalSpan('$input\n${displayLines.join('\n')}\n', isOutput: true));
      });
      _scrollToBottom();

      // Apply partial completion if available
      if (result.completedText != null && result.completedText!.length > input.length) {
        _inputController.text = result.completedText!;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      }
    } else if (input.isEmpty) {
      // No input - show all available commands
      final emptyResult = completer.complete('', currentPath);
      if (emptyResult.candidates.isNotEmpty) {
        final displayLines = completer.formatCandidatesForDisplay(emptyResult.candidates);
        setState(() {
          _spans.add(_TerminalSpan(_controller.getPrompt(), isPrompt: true));
          _spans.add(_TerminalSpan('\n${displayLines.join('\n')}\n', isOutput: true));
        });
        _scrollToBottom();
      }
    }
  }

  /// Handle keyboard events
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Up arrow - previous command
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_commandHistory.isNotEmpty && _historyIndex > 0) {
        _historyIndex--;
        _inputController.text = _commandHistory[_historyIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      }
      return KeyEventResult.handled;
    }

    // Down arrow - next command
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex < _commandHistory.length - 1) {
        _historyIndex++;
        _inputController.text = _commandHistory[_historyIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      } else {
        _historyIndex = _commandHistory.length;
        _inputController.clear();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Handle paste from clipboard
  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final text = data!.text!;
      final selection = _inputController.selection;
      final currentText = _inputController.text;

      // Insert at cursor position or replace selection
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      _inputController.text = newText;
      _inputController.selection = TextSelection.collapsed(
        offset: selection.start + text.length,
      );
    }
  }

  /// Build TextSpan list from terminal spans (including inline input)
  List<InlineSpan> _buildTextSpans() {
    final spans = <InlineSpan>[];

    // Add history spans
    for (final span in _spans) {
      spans.add(TextSpan(
        text: span.text,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontSize: 14,
          color: span.isPrompt ? _promptColor : _textColor,
          height: 1.2,
        ),
      ));
    }

    // Add current prompt inline
    spans.add(TextSpan(
      text: _controller.getPrompt(),
      style: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 14,
        color: _promptColor,
        height: 1.2,
      ),
    ));

    // Add input field inline using WidgetSpan
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: IntrinsicWidth(
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.tab): const _TabIntent(),
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV): const _PasteIntent(),
          },
          child: Actions(
            actions: {
              _TabIntent: CallbackAction<_TabIntent>(
                onInvoke: (_) {
                  _handleTabCompletion();
                  return null;
                },
              ),
              _PasteIntent: CallbackAction<_PasteIntent>(
                onInvoke: (_) {
                  _handlePaste();
                  return null;
                },
              ),
            },
            child: Focus(
              onKeyEvent: _handleKeyEvent,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: !_isProcessing,
                  maxLines: 1,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontFamilyFallback: _fontFamilyFallback,
                    fontSize: 14,
                    color: _textColor,
                    height: 1.2,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 200),
                  ),
                  cursorColor: _textColor,
                  onSubmitted: _submitCommand,
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? Colors.black : const Color(0xFF1E1E1E);
    _textColor = isDark ? Colors.green[300]! : Colors.green[400]!;
    _promptColor = isDark ? Colors.cyan[300]! : Colors.cyan[400]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('console')),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: _i18n.t('clear'),
            onPressed: () {
              setState(() => _spans.clear());
            },
          ),
        ],
      ),
      body: SelectionArea(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.translucent,
          child: SizedBox.expand(
            child: Container(
              color: backgroundColor,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // All terminal content - horizontally scrollable for ASCII art
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text.rich(
                          TextSpan(children: _buildTextSpans()),
                          softWrap: false,
                        ),
                      ),

                      // Extra space at bottom for scrolling
                      const SizedBox(height: 200),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A terminal span with style info
class _TerminalSpan {
  final String text;
  final bool isPrompt;
  final bool isOutput;

  _TerminalSpan(this.text, {this.isPrompt = false, this.isOutput = false});
}

/// Intent for TAB key
class _TabIntent extends Intent {
  const _TabIntent();
}

/// Intent for paste (CTRL+V)
class _PasteIntent extends Intent {
  const _PasteIntent();
}
