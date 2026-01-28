/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/spreadsheet_content.dart';
import '../../services/formula_service.dart';

/// A spreadsheet grid widget
class SheetGridWidget extends StatefulWidget {
  final SpreadsheetSheet sheet;
  final ValueChanged<SpreadsheetSheet> onChanged;
  final bool readOnly;

  const SheetGridWidget({
    super.key,
    required this.sheet,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<SheetGridWidget> createState() => _SheetGridWidgetState();
}

/// Represents a cell snapshot for clipboard and undo operations
class _CellSnapshot {
  final int row;
  final int col;
  final dynamic value;
  final CellType? type;
  final String? formula;
  final String? format;
  final String? styleId;
  final CellStyle? style;

  _CellSnapshot({
    required this.row,
    required this.col,
    this.value,
    this.type,
    this.formula,
    this.format,
    this.styleId,
    this.style,
  });

  factory _CellSnapshot.fromCell(int row, int col, SpreadsheetCell? cell, CellStyle? style) {
    return _CellSnapshot(
      row: row,
      col: col,
      value: cell?.value,
      type: cell?.type,
      formula: cell?.formula,
      format: cell?.format,
      styleId: cell?.style,
      style: style != null ? CellStyle(
        fontSize: style.fontSize,
        bold: style.bold,
        italic: style.italic,
        textColor: style.textColor,
        backgroundColor: style.backgroundColor,
      ) : null,
    );
  }
}

/// Represents an undo action
class _UndoAction {
  final List<_CellSnapshot> before;
  final List<_CellSnapshot> after;

  _UndoAction({required this.before, required this.after});
}

class _SheetGridWidgetState extends State<SheetGridWidget> {
  final _formulaService = FormulaService();
  final _scrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  final _rowNumbersScrollController = ScrollController();

  int? _selectedRow;
  int? _selectedCol;
  bool _isEditing = false;
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();
  final _gridFocusNode = FocusNode();

  // Clipboard and undo
  _CellSnapshot? _clipboard;
  final List<_UndoAction> _undoStack = [];
  static const _maxUndoHistory = 50;

  // Formula autocomplete state
  OverlayEntry? _autocompleteOverlay;
  List<(String, String, String)> _filteredFunctions = [];
  int _selectedFunctionIndex = 0;

  // Formula cell selection state
  (int, int)? _formulaRangeStart;
  (int, int)? _formulaRangeEnd;
  bool _isDraggingFormulaRange = false;

  // Column resize state
  bool _isResizingColumn = false;
  int? _resizingColumnIndex;
  double _resizeStartX = 0;
  double _resizeStartWidth = 0;

  static const _headerHeight = 32.0;
  static const _rowNumberWidth = 50.0;
  static const _defaultColWidth = 100.0;
  static const _defaultRowHeight = 28.0;
  static const _toolbarHeight = 40.0;

  // Color presets for cell formatting
  static const _colorPresets = [
    ('#000000', 'Black'),
    ('#FFFFFF', 'White'),
    ('#FF0000', 'Red'),
    ('#00AA00', 'Green'),
    ('#0000FF', 'Blue'),
    ('#FFFF00', 'Yellow'),
    ('#FF00FF', 'Magenta'),
    ('#00FFFF', 'Cyan'),
    ('#FFA500', 'Orange'),
    ('#800080', 'Purple'),
  ];

  // Font size presets
  static const _fontSizePresets = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0];

  @override
  void initState() {
    super.initState();
    // Sync row numbers scroll with main grid scroll
    _scrollController.addListener(_syncRowNumbersScroll);
    // Listen for formula typing to show autocomplete
    _editController.addListener(_onFormulaTextChanged);
    // Initialize selection from saved state (defaults to A1)
    _selectedRow = widget.sheet.selectedRow;
    _selectedCol = widget.sheet.selectedCol;
    // Load initial cell content into formula bar
    final cell = widget.sheet.getCell(_selectedRow!, _selectedCol!);
    _editController.text = cell?.formula ?? cell?.value?.toString() ?? '';
  }

  void _syncRowNumbersScroll() {
    if (_rowNumbersScrollController.hasClients) {
      _rowNumbersScrollController.jumpTo(_scrollController.offset);
    }
  }

  // Formula autocomplete methods

  void _onFormulaTextChanged() {
    final text = _editController.text;

    // Hide if not a formula
    if (!text.startsWith('=')) {
      _hideAutocomplete();
      return;
    }

    // Extract what comes after "=" (the function name being typed)
    final afterEquals = text.substring(1);

    // If just "=" or "=ABC" (no parenthesis yet), show autocomplete
    if (!afterEquals.contains('(')) {
      final prefix = afterEquals.toUpperCase();

      // Show all functions when just "=", or filter by prefix
      if (prefix.isEmpty) {
        _filteredFunctions = FormulaService.formulaFunctions.toList();
      } else {
        _filteredFunctions = FormulaService.formulaFunctions
            .where((f) => f.$1.startsWith(prefix))
            .toList();
      }

      _selectedFunctionIndex = 0;
      if (_filteredFunctions.isNotEmpty) {
        _showAutocomplete();
      } else {
        _hideAutocomplete();
      }
    } else {
      // User has opened parenthesis, hide autocomplete
      _hideAutocomplete();
    }
  }

  void _showAutocomplete() {
    _hideAutocomplete();

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);

    _autocompleteOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + _rowNumberWidth + 76, // After cell ref
        top: position.dy + _toolbarHeight + 36, // Below formula bar
        child: _buildAutocompleteDropdown(),
      ),
    );

    overlay.insert(_autocompleteOverlay!);
  }

  void _hideAutocomplete() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
  }

  // Formula cell selection helpers

  bool get _canSelectCellForFormula =>
      _isEditing &&
      _editController.text.startsWith('=') &&
      _autocompleteOverlay == null;

  String _formatCellRef(int row, int col) {
    return '${SpreadsheetSheet.columnLetter(col)}${row + 1}';
  }

  String _formatRangeRef((int, int) start, (int, int) end) {
    if (start == end) return _formatCellRef(start.$1, start.$2);

    final minRow = start.$1 < end.$1 ? start.$1 : end.$1;
    final maxRow = start.$1 > end.$1 ? start.$1 : end.$1;
    final minCol = start.$2 < end.$2 ? start.$2 : end.$2;
    final maxCol = start.$2 > end.$2 ? start.$2 : end.$2;

    return '${_formatCellRef(minRow, minCol)}:${_formatCellRef(maxRow, maxCol)}';
  }

  void _insertCellReference(String cellRef) {
    final text = _editController.text;
    final selection = _editController.selection;
    final cursorPos = selection.isValid ? selection.baseOffset : text.length;

    // Check if we need to add a closing parenthesis
    // Count unclosed parentheses before cursor
    final textBeforeCursor = text.substring(0, cursorPos);
    int openParens = 0;
    for (final char in textBeforeCursor.split('')) {
      if (char == '(') openParens++;
      if (char == ')') openParens--;
    }

    // Add closing paren if there's an unclosed one
    final suffix = openParens > 0 ? ')' : '';
    final newText = text.substring(0, cursorPos) + cellRef + suffix + text.substring(cursorPos);
    _editController.text = newText;
    _editController.selection = TextSelection.collapsed(offset: cursorPos + cellRef.length + suffix.length);
    _editFocusNode.requestFocus();
  }

  bool _isInFormulaSelectionRange(int row, int col) {
    if (!_isDraggingFormulaRange || _formulaRangeStart == null) return false;

    final start = _formulaRangeStart!;
    final end = _formulaRangeEnd ?? start;

    final minRow = start.$1 < end.$1 ? start.$1 : end.$1;
    final maxRow = start.$1 > end.$1 ? start.$1 : end.$1;
    final minCol = start.$2 < end.$2 ? start.$2 : end.$2;
    final maxCol = start.$2 > end.$2 ? start.$2 : end.$2;

    return row >= minRow && row <= maxRow && col >= minCol && col <= maxCol;
  }

  (int, int)? _hitTestCell(Offset globalPosition) {
    final RenderBox? gridBox = context.findRenderObject() as RenderBox?;
    if (gridBox == null) return null;

    final localPosition = gridBox.globalToLocal(globalPosition);
    final yOffset = localPosition.dy - _toolbarHeight - 36 - _headerHeight + _scrollController.offset;
    final xOffset = localPosition.dx - _rowNumberWidth + _horizontalScrollController.offset;

    if (yOffset < 0 || xOffset < 0) return null;

    // Find row by accumulated height
    int row = 0;
    double accHeight = 0;
    while (row < widget.sheet.rows && accHeight + _getRowHeight(row) <= yOffset) {
      accHeight += _getRowHeight(row);
      row++;
    }

    // Find column by accumulated width
    int col = 0;
    double accWidth = 0;
    while (col < widget.sheet.cols && accWidth + _getColumnWidth(col) <= xOffset) {
      accWidth += _getColumnWidth(col);
      col++;
    }

    if (row >= widget.sheet.rows || col >= widget.sheet.cols) return null;
    return (row, col);
  }

  void _cancelFormulaRangeSelection() {
    setState(() {
      _isDraggingFormulaRange = false;
      _formulaRangeStart = null;
      _formulaRangeEnd = null;
    });
  }

  void _onCellPanStart(int row, int col, DragStartDetails details) {
    if (!_canSelectCellForFormula) return;
    _hideAutocomplete();
    setState(() {
      _isDraggingFormulaRange = true;
      _formulaRangeStart = (row, col);
      _formulaRangeEnd = (row, col);
    });
  }

  void _onCellPanUpdate(DragUpdateDetails details) {
    if (!_isDraggingFormulaRange || _formulaRangeStart == null) return;
    final cellPos = _hitTestCell(details.globalPosition);
    if (cellPos != null && cellPos != _formulaRangeEnd) {
      setState(() {
        _formulaRangeEnd = cellPos;
      });
    }
  }

  void _onCellPanEnd(DragEndDetails details) {
    if (!_isDraggingFormulaRange || _formulaRangeStart == null) return;

    final rangeRef = _formatRangeRef(_formulaRangeStart!, _formulaRangeEnd ?? _formulaRangeStart!);
    _insertCellReference(rangeRef);
    _cancelFormulaRangeSelection();
  }

  void _updateAutocomplete() {
    _autocompleteOverlay?.markNeedsBuild();
  }

  Widget _buildAutocompleteDropdown() {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _filteredFunctions.length,
          itemBuilder: (context, index) {
            final (name, desc, _) = _filteredFunctions[index];
            final isSelected = index == _selectedFunctionIndex;

            return InkWell(
              onTap: () => _insertFunction(name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: isSelected ? theme.colorScheme.primaryContainer : null,
                child: Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        desc,
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _insertFunction(String functionName) {
    // Replace the partial function name with full name + opening paren
    final newText = '=$functionName(';
    _editController.text = newText;
    _editController.selection = TextSelection.collapsed(offset: newText.length);
    _hideAutocomplete();
    _editFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncRowNumbersScroll);
    _editController.removeListener(_onFormulaTextChanged);
    _hideAutocomplete();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _rowNumbersScrollController.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
    _gridFocusNode.dispose();
    super.dispose();
  }

  double _getColumnWidth(int col) {
    return widget.sheet.columns[col]?.width ?? _defaultColWidth;
  }

  double _getRowHeight(int row) {
    return widget.sheet.rowDefs[row]?.height ?? _defaultRowHeight;
  }

  // Column resize methods

  void _onColumnResizeStart(int col, DragStartDetails details) {
    setState(() {
      _isResizingColumn = true;
      _resizingColumnIndex = col;
      _resizeStartX = details.globalPosition.dx;
      _resizeStartWidth = _getColumnWidth(col);
    });
  }

  void _onColumnResizeUpdate(DragUpdateDetails details) {
    if (!_isResizingColumn || _resizingColumnIndex == null) return;

    final delta = details.globalPosition.dx - _resizeStartX;
    final newWidth = (_resizeStartWidth + delta).clamp(30.0, 500.0);

    // Update or create column definition
    final col = _resizingColumnIndex!;
    if (widget.sheet.columns[col] == null) {
      widget.sheet.columns[col] = SpreadsheetColumn(width: newWidth);
    } else {
      widget.sheet.columns[col]!.width = newWidth;
    }

    setState(() {});
  }

  void _onColumnResizeEnd(DragEndDetails details) {
    if (_isResizingColumn) {
      widget.onChanged(widget.sheet); // Persist changes
    }
    setState(() {
      _isResizingColumn = false;
      _resizingColumnIndex = null;
    });
  }

  void _selectCell(int row, int col) {
    // Insert cell reference if in formula editing mode
    if (_canSelectCellForFormula) {
      _hideAutocomplete();
      _insertCellReference(_formatCellRef(row, col));
      return;  // Stay in editing mode, don't navigate
    }

    if (_isEditing) {
      _commitEdit();
    }
    _hideAutocomplete();
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
      _isEditing = false;
      // Update formula bar to show selected cell's content
      final cell = widget.sheet.getCell(row, col);
      _editController.text = cell?.formula ?? cell?.value?.toString() ?? '';
    });
    // Save selection to model for persistence
    widget.sheet.selectedRow = row;
    widget.sheet.selectedCol = col;
    widget.onChanged(widget.sheet);
    // Request focus so keyboard events go to the grid
    _gridFocusNode.requestFocus();
  }

  void _startEditing({String? initialText}) {
    if (widget.readOnly) return;
    if (_selectedRow == null || _selectedCol == null) return;

    if (_isEditing && initialText != null) {
      // Already editing - append the character at cursor position, don't replace
      final currentText = _editController.text;
      final selection = _editController.selection;
      final newText = currentText.substring(0, selection.start) +
          initialText +
          currentText.substring(selection.end);
      _editController.text = newText;
      _editController.selection = TextSelection.collapsed(
        offset: selection.start + initialText.length,
      );
      _editFocusNode.requestFocus();
      return;
    }

    // Starting fresh edit
    if (initialText != null) {
      _editController.text = initialText;
    } else {
      final cell = widget.sheet.getCell(_selectedRow!, _selectedCol!);
      _editController.text = cell?.formula ?? cell?.value?.toString() ?? '';
    }

    setState(() {
      _isEditing = true;
    });

    _editFocusNode.requestFocus();
    _editController.selection = TextSelection.collapsed(
      offset: _editController.text.length,
    );
  }

  void _commitEdit() {
    if (_selectedRow == null || _selectedCol == null) return;

    _hideAutocomplete();
    _cancelFormulaRangeSelection();

    // Save undo state before making changes
    _saveUndoState();

    final text = _editController.text;
    final cell = widget.sheet.getOrCreateCell(_selectedRow!, _selectedCol!);

    if (text.isEmpty) {
      widget.sheet.deleteCell(_selectedRow!, _selectedCol!);
    } else if (text.startsWith('=')) {
      cell.formula = text;
      cell.value = _formulaService.evaluate(text, widget.sheet);
    } else {
      cell.formula = null;
      // Try to parse as number
      final num? number = num.tryParse(text);
      if (number != null) {
        cell.value = number;
        cell.type = number is int ? CellType.number : CellType.number;
      } else {
        cell.value = text;
        cell.type = CellType.string;
      }
    }

    setState(() {
      _isEditing = false;
    });

    widget.onChanged(widget.sheet);
  }

  void _cancelEdit() {
    _hideAutocomplete();
    _cancelFormulaRangeSelection();
    setState(() {
      _isEditing = false;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Handle autocomplete keyboard navigation first
    if (_autocompleteOverlay != null) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _selectedFunctionIndex = (_selectedFunctionIndex + 1) % _filteredFunctions.length;
        _updateAutocomplete();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _selectedFunctionIndex = (_selectedFunctionIndex - 1 + _filteredFunctions.length) % _filteredFunctions.length;
        _updateAutocomplete();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.tab) {
        _insertFunction(_filteredFunctions[_selectedFunctionIndex].$1);
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _hideAutocomplete();
        return;
      }
    }

    // Handle Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+S regardless of editing state
    if (isCtrl) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _copyCell();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
        _pasteCell();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        _undo();
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _saveDocument();
        return;
      }
    }

    if (_isEditing) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // If dragging a formula range, just cancel the drag
        if (_isDraggingFormulaRange) {
          _cancelFormulaRangeSelection();
        } else {
          _cancelEdit();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _commitEdit();
        _moveSelection(1, 0);
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        _commitEdit();
        _moveSelection(0, 1);
      }
      return;
    }

    // Navigation when not editing
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, 0);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, 0);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(0, -1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveSelection(0, 1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.f2) {
      _startEditing();
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
               event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedCell();
    } else if (event.character != null &&
               event.character!.isNotEmpty &&
               !isCtrl) {
      // Start typing to edit with the typed character
      _startEditing(initialText: event.character!);
    }
  }

  void _moveSelection(int dRow, int dCol) {
    final newRow = (_selectedRow ?? 0) + dRow;
    final newCol = (_selectedCol ?? 0) + dCol;

    if (newRow >= 0 && newRow < widget.sheet.rows &&
        newCol >= 0 && newCol < widget.sheet.cols) {
      _selectCell(newRow, newCol);
    }
  }

  void _deleteSelectedCell() {
    if (widget.readOnly) return;
    if (_selectedRow == null || _selectedCol == null) return;

    _saveUndoState();
    widget.sheet.deleteCell(_selectedRow!, _selectedCol!);
    _editController.text = '';
    setState(() {});
    widget.onChanged(widget.sheet);
  }

  String _getCellDisplayValue(int row, int col) {
    final cell = widget.sheet.getCell(row, col);
    if (cell == null) return '';

    if (cell.hasFormula) {
      final result = _formulaService.evaluate(cell.formula!, widget.sheet);
      if (result is num) {
        // Format numbers nicely
        if (result == result.toInt()) {
          return result.toInt().toString();
        }
        return result.toStringAsFixed(2);
      }
      return result.toString();
    }

    return cell.displayValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return KeyboardListener(
      focusNode: _gridFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        children: [
          // Toolbar with copy/paste/undo icons
          _buildToolbar(theme),
          // Formula bar - always visible
          _buildFormulaBar(theme),
          // Grid
          Expanded(
            child: _buildGrid(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final hasClipboard = _clipboard != null;
    final canUndo = _undoStack.isNotEmpty;
    final hasSelection = _selectedRow != null && _selectedCol != null;

    // Get current cell's currency format for the toolbar button
    final cell = hasSelection
        ? widget.sheet.getCell(_selectedRow!, _selectedCol!)
        : null;
    final currentCurrency = cell?.format != null
        ? CurrencyFormat.byCode(cell!.format!)
        : null;

    final currencyButtonEnabled = hasSelection && !widget.readOnly;
    final currencyButtonColor = currencyButtonEnabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Container(
      height: _toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Copy button
          _ToolbarButton(
            icon: Icons.content_copy,
            tooltip: 'Copy (Ctrl+C)',
            enabled: hasSelection,
            onPressed: _copyCell,
          ),
          const SizedBox(width: 4),
          // Paste button
          _ToolbarButton(
            icon: Icons.content_paste,
            tooltip: 'Paste (Ctrl+V)',
            enabled: hasClipboard && hasSelection && !widget.readOnly,
            onPressed: _pasteCell,
          ),
          const SizedBox(width: 4),
          // Undo button
          _ToolbarButton(
            icon: Icons.undo,
            tooltip: 'Undo (Ctrl+Z)',
            enabled: canUndo && !widget.readOnly,
            onPressed: _undo,
          ),
          const SizedBox(width: 4),
          // Divider
          VerticalDivider(
            width: 16,
            indent: 8,
            endIndent: 8,
            color: theme.colorScheme.outlineVariant,
          ),
          // Bold button
          _ToolbarButton(
            icon: Icons.format_bold,
            tooltip: 'Bold',
            enabled: hasSelection && !widget.readOnly,
            onPressed: _toggleBold,
          ),
          const SizedBox(width: 4),
          // Italic button
          _ToolbarButton(
            icon: Icons.format_italic,
            tooltip: 'Italic',
            enabled: hasSelection && !widget.readOnly,
            onPressed: _toggleItalic,
          ),
          const SizedBox(width: 4),
          // Currency button - shows current currency symbol or default icon
          _ToolbarButton(
            tooltip: currentCurrency != null
                ? 'Currency: ${currentCurrency.name} (${currentCurrency.code})'
                : 'Currency Format',
            enabled: currencyButtonEnabled,
            onPressed: _showCurrencyMenu,
            child: currentCurrency != null
                ? Text(
                    currentCurrency.symbol,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: currencyButtonColor,
                    ),
                  )
                : Icon(
                    Icons.attach_money,
                    size: 20,
                    color: currencyButtonColor,
                  ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFormulaBar(ThemeData theme) {
    final cellRef = _selectedRow != null && _selectedCol != null
        ? '${SpreadsheetSheet.columnLetter(_selectedCol!)}${_selectedRow! + 1}'
        : '';

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Cell reference
          Container(
            width: 60,
            alignment: Alignment.center,
            child: Text(
              cellRef,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          VerticalDivider(
            width: 16,
            color: theme.colorScheme.outlineVariant,
          ),
          // Formula/value display - TextField always mounted to avoid timing issues
          Expanded(
            child: TextField(
              controller: _editController,
              focusNode: _editFocusNode,
              readOnly: widget.readOnly,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onTap: () {
                if (!_isEditing && _selectedRow != null && _selectedCol != null) {
                  _startEditing();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleCols = widget.sheet.cols;
        final visibleRows = widget.sheet.rows;

        return Stack(
          children: [
            // Main grid
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _horizontalScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      _buildHeaderRow(theme, visibleCols),
                      // Data rows
                      for (var row = 0; row < visibleRows; row++)
                        _buildDataRow(theme, row, visibleCols),
                    ],
                  ),
                ),
              ),
            ),
            // Frozen row numbers column (synced with main grid scroll)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _rowNumberWidth,
              child: IgnorePointer(
                child: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: SingleChildScrollView(
                    controller: _rowNumbersScrollController,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                    children: [
                      // Corner cell
                      Container(
                        height: _headerHeight,
                        width: _rowNumberWidth,
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: theme.colorScheme.outlineVariant),
                            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                      ),
                      // Row numbers
                      for (var row = 0; row < visibleRows; row++)
                        _buildRowNumber(theme, row),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderRow(ThemeData theme, int cols) {
    return Row(
      children: [
        SizedBox(width: _rowNumberWidth), // Space for row numbers
        for (var col = 0; col < cols; col++)
          _buildColumnHeader(theme, col),
      ],
    );
  }

  Widget _buildColumnHeader(ThemeData theme, int col) {
    final width = _getColumnWidth(col);
    final isResizing = _isResizingColumn && _resizingColumnIndex == col;

    return SizedBox(
      width: width,
      height: _headerHeight,
      child: Stack(
        children: [
          // Main header content
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              SpreadsheetSheet.columnLetter(col),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Resize handle on right edge
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onPanStart: (details) => _onColumnResizeStart(col, details),
                onPanUpdate: _onColumnResizeUpdate,
                onPanEnd: _onColumnResizeEnd,
                child: Container(
                  width: 8,
                  color: isResizing
                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowNumber(ThemeData theme, int row) {
    final height = _getRowHeight(row);
    final isSelected = _selectedRow == row;

    return Container(
      width: _rowNumberWidth,
      height: height,
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${row + 1}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDataRow(ThemeData theme, int row, int cols) {
    final height = _getRowHeight(row);

    return Row(
      children: [
        SizedBox(width: _rowNumberWidth), // Space for row numbers
        for (var col = 0; col < cols; col++)
          _buildCell(theme, row, col, height),
      ],
    );
  }

  Widget _buildCell(ThemeData theme, int row, int col, double height) {
    final width = _getColumnWidth(col);
    final isSelected = _selectedRow == row && _selectedCol == col;
    final cell = widget.sheet.getCell(row, col);
    final cellBgColor = _getCellBackgroundColor(cell);
    final cellTextStyle = _getCellTextStyle(cell, theme);

    // Check if cell is in formula selection range
    final isInFormulaRange = _isInFormulaSelectionRange(row, col);

    // Determine background color
    Color? bgColor;
    if (isInFormulaRange) {
      bgColor = theme.colorScheme.tertiary.withValues(alpha: 0.3);
    } else if (isSelected) {
      bgColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
    } else {
      bgColor = cellBgColor;
    }

    return GestureDetector(
      onTap: () => _selectCell(row, col),
      onDoubleTap: () {
        _selectCell(row, col);
        _startEditing();
      },
      onSecondaryTapDown: (details) =>
          _showCellContextMenu(row, col, details.globalPosition),
      onLongPress: () => _showCellContextMenuAtCell(row, col),
      onPanStart: (details) => _onCellPanStart(row, col, details),
      onPanUpdate: _onCellPanUpdate,
      onPanEnd: _onCellPanEnd,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            right: BorderSide(color: theme.colorScheme.outlineVariant),
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: isSelected && _isEditing
            ? ValueListenableBuilder<TextEditingValue>(
                valueListenable: _editController,
                builder: (context, value, child) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value.text,
                    style: cellTextStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: _getAlignment(cell),
                child: Text(
                  _getCellDisplayValue(row, col),
                  style: cellTextStyle.copyWith(
                    fontWeight: cell?.hasFormula == true
                        ? FontWeight.w500
                        : cellTextStyle.fontWeight,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
      ),
    );
  }

  Alignment _getAlignment(SpreadsheetCell? cell) {
    if (cell == null) return Alignment.centerLeft;

    // Numbers align right by default
    if (cell.value is num) {
      return Alignment.centerRight;
    }

    return Alignment.centerLeft;
  }

  // Parse hex color string to Color
  Color? _parseColor(String? colorStr) {
    if (colorStr == null || !colorStr.startsWith('#')) return null;
    final hex = colorStr.substring(1);
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    return null;
  }

  // Get TextStyle for a cell based on its CellStyle
  TextStyle _getCellTextStyle(SpreadsheetCell? cell, ThemeData theme) {
    final baseStyle = theme.textTheme.bodySmall ?? const TextStyle();
    if (cell?.style == null) return baseStyle;

    final cellStyle = widget.sheet.styles[cell!.style];
    if (cellStyle == null) return baseStyle;

    return baseStyle.copyWith(
      fontSize: cellStyle.fontSize,
      fontWeight: cellStyle.bold == true ? FontWeight.bold : null,
      fontStyle: cellStyle.italic == true ? FontStyle.italic : null,
      color: _parseColor(cellStyle.textColor),
    );
  }

  // Get background color for a cell
  Color? _getCellBackgroundColor(SpreadsheetCell? cell) {
    if (cell?.style == null) return null;
    final cellStyle = widget.sheet.styles[cell!.style];
    return _parseColor(cellStyle?.backgroundColor);
  }

  // Show context menu for cell formatting
  void _showCellContextMenu(int row, int col, Offset globalPosition) {
    if (widget.readOnly) return;
    _selectCell(row, col);

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _buildContextMenuItems(),
    ).then((value) {
      if (value != null) {
        _handleContextMenuAction(value);
      }
    });
  }

  // Show context menu at cell position (for long press on mobile)
  void _showCellContextMenuAtCell(int row, int col) {
    if (widget.readOnly) return;
    _selectCell(row, col);

    // Calculate position based on cell location
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Approximate position - center of screen
    final size = box.size;
    final position = Offset(size.width / 2, size.height / 2);
    final globalPos = box.localToGlobal(position);

    _showCellContextMenu(row, col, globalPos);
  }

  List<PopupMenuEntry<String>> _buildContextMenuItems() {
    final cell = _selectedRow != null && _selectedCol != null
        ? widget.sheet.getCell(_selectedRow!, _selectedCol!)
        : null;
    final cellStyle = cell?.style != null
        ? widget.sheet.styles[cell!.style]
        : null;

    return [
      // Bold toggle
      PopupMenuItem<String>(
        value: 'bold',
        child: Row(
          children: [
            Icon(
              Icons.format_bold,
              size: 20,
              color: cellStyle?.bold == true ? Colors.blue : null,
            ),
            const SizedBox(width: 8),
            const Text('Bold'),
            if (cellStyle?.bold == true) ...[
              const Spacer(),
              const Icon(Icons.check, size: 16),
            ],
          ],
        ),
      ),
      // Italic toggle
      PopupMenuItem<String>(
        value: 'italic',
        child: Row(
          children: [
            Icon(
              Icons.format_italic,
              size: 20,
              color: cellStyle?.italic == true ? Colors.blue : null,
            ),
            const SizedBox(width: 8),
            const Text('Italic'),
            if (cellStyle?.italic == true) ...[
              const Spacer(),
              const Icon(Icons.check, size: 16),
            ],
          ],
        ),
      ),
      const PopupMenuDivider(),
      // Font Size submenu
      PopupMenuItem<String>(
        value: 'fontSize',
        child: Row(
          children: [
            const Icon(Icons.format_size, size: 20),
            const SizedBox(width: 8),
            const Text('Font Size'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 16),
          ],
        ),
      ),
      // Text Color submenu
      PopupMenuItem<String>(
        value: 'textColor',
        child: Row(
          children: [
            const Icon(Icons.format_color_text, size: 20),
            const SizedBox(width: 8),
            const Text('Text Color'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 16),
          ],
        ),
      ),
      // Background Color submenu
      PopupMenuItem<String>(
        value: 'backgroundColor',
        child: Row(
          children: [
            const Icon(Icons.format_color_fill, size: 20),
            const SizedBox(width: 8),
            const Text('Background Color'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 16),
          ],
        ),
      ),
      const PopupMenuDivider(),
      // Currency Format submenu
      PopupMenuItem<String>(
        value: 'currency',
        child: Row(
          children: [
            const Icon(Icons.attach_money, size: 20),
            const SizedBox(width: 8),
            Text('Currency${cell?.format != null && CurrencyFormat.byCode(cell!.format!) != null ? ' (${cell.format})' : ''}'),
            const Spacer(),
            const Icon(Icons.arrow_right, size: 16),
          ],
        ),
      ),
      const PopupMenuDivider(),
      // Clear Formatting
      const PopupMenuItem<String>(
        value: 'clearFormatting',
        child: Row(
          children: [
            Icon(Icons.format_clear, size: 20),
            SizedBox(width: 8),
            Text('Clear Formatting'),
          ],
        ),
      ),
    ];
  }

  void _handleContextMenuAction(String action) {
    switch (action) {
      case 'bold':
        _toggleBold();
        break;
      case 'italic':
        _toggleItalic();
        break;
      case 'fontSize':
        _showFontSizeMenu();
        break;
      case 'textColor':
        _showColorMenu(isBackground: false);
        break;
      case 'backgroundColor':
        _showColorMenu(isBackground: true);
        break;
      case 'currency':
        _showCurrencyMenu();
        break;
      case 'clearFormatting':
        _clearFormatting();
        break;
    }
  }

  void _showFontSizeMenu() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final position = Offset(size.width / 2, size.height / 2);
    final globalPos = box.localToGlobal(position);

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<double>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _fontSizePresets.map((size) {
        return PopupMenuItem<double>(
          value: size,
          child: Text('${size.toInt()} pt'),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        _setFontSize(value);
      }
    });
  }

  void _showColorMenu({required bool isBackground}) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final position = Offset(size.width / 2, size.height / 2);
    final globalPos = box.localToGlobal(position);

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        // None/Clear option
        PopupMenuItem<String>(
          value: 'none',
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Icon(Icons.block, size: 12, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              const Text('None'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ..._colorPresets.map((preset) {
          final (hex, name) = preset;
          return PopupMenuItem<String>(
            value: hex,
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _parseColor(hex),
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(name),
              ],
            ),
          );
        }),
      ],
    ).then((value) {
      if (value != null) {
        if (isBackground) {
          _setBackgroundColor(value == 'none' ? null : value);
        } else {
          _setTextColor(value == 'none' ? null : value);
        }
      }
    });
  }

  void _showCurrencyMenu() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final position = Offset(size.width / 2, size.height / 2);
    final globalPos = box.localToGlobal(position);

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final cell = _selectedRow != null && _selectedCol != null
        ? widget.sheet.getCell(_selectedRow!, _selectedCol!)
        : null;
    final currentFormat = cell?.format;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        // None/Clear option
        PopupMenuItem<String>(
          value: 'none',
          child: Row(
            children: [
              const Icon(Icons.block, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              const Text('None (Number)'),
              if (currentFormat == null) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Crypto currencies header (first, with Monero on top)
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            'CRYPTOCURRENCIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...CurrencyFormat.cryptoCurrencies.map((currency) {
          final isSelected = currentFormat == currency.code;
          return PopupMenuItem<String>(
            value: currency.code,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    currency.symbol,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(currency.name)),
                Text(
                  currency.code,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, size: 16),
                ],
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        // Fiat currencies header
        const PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            'FIAT CURRENCIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...CurrencyFormat.fiatCurrencies.map((currency) {
          final isSelected = currentFormat == currency.code;
          return PopupMenuItem<String>(
            value: currency.code,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    currency.symbol,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(currency.name)),
                Text(
                  currency.code,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, size: 16),
                ],
              ],
            ),
          );
        }),
      ],
    ).then((value) {
      if (value != null) {
        _setCurrencyFormat(value == 'none' ? null : value);
      }
    });
  }

  void _setCurrencyFormat(String? currencyCode) {
    if (_selectedRow == null || _selectedCol == null) return;

    _saveUndoState();

    final cell = widget.sheet.getOrCreateCell(_selectedRow!, _selectedCol!);
    cell.format = currencyCode;

    // Set type to currency if a currency is selected, otherwise to number
    if (currencyCode != null) {
      cell.type = CellType.currency;
    } else if (cell.type == CellType.currency) {
      cell.type = CellType.number;
    }

    setState(() {});
    widget.onChanged(widget.sheet);
  }

  void _toggleBold() {
    _applyCellStyle((style) {
      style.bold = !(style.bold ?? false);
    });
  }

  void _toggleItalic() {
    _applyCellStyle((style) {
      style.italic = !(style.italic ?? false);
    });
  }

  void _setFontSize(double size) {
    _applyCellStyle((style) {
      style.fontSize = size;
    });
  }

  void _setTextColor(String? hexColor) {
    _applyCellStyle((style) {
      style.textColor = hexColor;
    });
  }

  void _setBackgroundColor(String? hexColor) {
    _applyCellStyle((style) {
      style.backgroundColor = hexColor;
    });
  }

  void _applyCellStyle(void Function(CellStyle) modifier) {
    if (_selectedRow == null || _selectedCol == null) return;

    // Save undo state before making changes
    _saveUndoState();

    final cell = widget.sheet.getOrCreateCell(_selectedRow!, _selectedCol!);
    final styleId =
        cell.style ?? 'style-${DateTime.now().millisecondsSinceEpoch}';

    final style = widget.sheet.styles[styleId] ?? CellStyle();
    modifier(style);

    widget.sheet.styles[styleId] = style;
    cell.style = styleId;

    setState(() {});
    widget.onChanged(widget.sheet);
  }

  void _clearFormatting() {
    if (_selectedRow == null || _selectedCol == null) return;
    final cell = widget.sheet.getCell(_selectedRow!, _selectedCol!);
    if (cell != null) {
      _saveUndoState();
      cell.style = null;
      cell.format = null;
      if (cell.type == CellType.currency) {
        cell.type = CellType.number;
      }
      setState(() {});
      widget.onChanged(widget.sheet);
    }
  }

  // Copy/Paste/Undo operations

  void _copyCell() {
    if (_selectedRow == null || _selectedCol == null) return;

    final cell = widget.sheet.getCell(_selectedRow!, _selectedCol!);
    final styleId = cell?.style;
    final style = styleId != null ? widget.sheet.styles[styleId] : null;

    _clipboard = _CellSnapshot.fromCell(_selectedRow!, _selectedCol!, cell, style);

    // Also copy to system clipboard for interop
    final text = cell?.formula ?? cell?.value?.toString() ?? '';
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
    }

    setState(() {});
  }

  void _pasteCell() {
    if (widget.readOnly) return;
    if (_selectedRow == null || _selectedCol == null) return;
    if (_clipboard == null) return;

    // Save current state for undo
    _saveUndoState();

    final targetCell = widget.sheet.getOrCreateCell(_selectedRow!, _selectedCol!);

    // Copy value and formula
    targetCell.value = _clipboard!.value;
    targetCell.type = _clipboard!.type;
    targetCell.formula = _clipboard!.formula;
    targetCell.format = _clipboard!.format;

    // Copy style if present
    if (_clipboard!.style != null) {
      final newStyleId = 'style-${DateTime.now().millisecondsSinceEpoch}';
      widget.sheet.styles[newStyleId] = CellStyle(
        fontSize: _clipboard!.style!.fontSize,
        bold: _clipboard!.style!.bold,
        italic: _clipboard!.style!.italic,
        textColor: _clipboard!.style!.textColor,
        backgroundColor: _clipboard!.style!.backgroundColor,
      );
      targetCell.style = newStyleId;
    } else {
      targetCell.style = null;
    }

    // Update formula bar
    _editController.text = targetCell.formula ?? targetCell.value?.toString() ?? '';

    setState(() {});
    widget.onChanged(widget.sheet);
  }

  void _saveUndoState() {
    if (_selectedRow == null || _selectedCol == null) return;

    final cell = widget.sheet.getCell(_selectedRow!, _selectedCol!);
    final styleId = cell?.style;
    final style = styleId != null ? widget.sheet.styles[styleId] : null;

    final before = [_CellSnapshot.fromCell(_selectedRow!, _selectedCol!, cell, style)];

    // We'll capture "after" state later, but for simplicity we store the before state
    // and let undo restore it
    _undoStack.add(_UndoAction(before: before, after: []));

    // Limit undo history
    while (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (widget.readOnly) return;
    if (_undoStack.isEmpty) return;

    final action = _undoStack.removeLast();

    for (final snapshot in action.before) {
      if (snapshot.value == null && snapshot.formula == null) {
        // Cell was empty before, delete it
        widget.sheet.deleteCell(snapshot.row, snapshot.col);
      } else {
        // Restore cell state
        final cell = widget.sheet.getOrCreateCell(snapshot.row, snapshot.col);
        cell.value = snapshot.value;
        cell.type = snapshot.type;
        cell.formula = snapshot.formula;
        cell.format = snapshot.format;

        if (snapshot.style != null) {
          final newStyleId = 'style-${DateTime.now().millisecondsSinceEpoch}';
          widget.sheet.styles[newStyleId] = CellStyle(
            fontSize: snapshot.style!.fontSize,
            bold: snapshot.style!.bold,
            italic: snapshot.style!.italic,
            textColor: snapshot.style!.textColor,
            backgroundColor: snapshot.style!.backgroundColor,
          );
          cell.style = newStyleId;
        } else {
          cell.style = null;
        }
      }

      // If this was the selected cell, update formula bar
      if (snapshot.row == _selectedRow && snapshot.col == _selectedCol) {
        final restoredCell = widget.sheet.getCell(snapshot.row, snapshot.col);
        _editController.text = restoredCell?.formula ?? restoredCell?.value?.toString() ?? '';
      }
    }

    setState(() {});
    widget.onChanged(widget.sheet);
  }

  void _saveDocument() {
    // Commit any pending edit first
    if (_isEditing) {
      _commitEdit();
    }
    // Trigger save via onChanged callback
    widget.onChanged(widget.sheet);
  }

}

/// Toolbar button widget
class _ToolbarButton extends StatelessWidget {
  final IconData? icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final Widget? child;

  const _ToolbarButton({
    this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.child,
  }) : assert(icon != null || child != null, 'Either icon or child must be provided');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: child ?? Icon(
            icon,
            size: 20,
            color: color,
          ),
        ),
      ),
    );
  }
}
