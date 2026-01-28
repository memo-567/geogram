/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/document_content.dart';
import '../services/ndf_service.dart';
import '../widgets/document/rich_text_widget.dart';

/// Document editor page for rich text documents
class DocumentEditorPage extends StatefulWidget {
  final String filePath;
  final String? title;

  const DocumentEditorPage({
    super.key,
    required this.filePath,
    this.title,
  });

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  final I18nService _i18n = I18nService();
  final NdfService _ndfService = NdfService();

  NdfDocument? _metadata;
  DocumentContent? _content;
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _error;

  String? _editingElementId;
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();

  // Formatting state
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load metadata
      final metadata = await _ndfService.readMetadata(widget.filePath);
      if (metadata == null) {
        throw Exception('Could not read document metadata');
      }

      // Load content
      final content = await _ndfService.readDocumentContent(widget.filePath);

      setState(() {
        _metadata = metadata;
        _content = content ?? DocumentContent.create();
        _isLoading = false;
      });
    } catch (e) {
      LogService().log('DocumentEditorPage: Error loading document: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_content == null || _metadata == null) return;

    // Commit any pending edits
    _commitEdit();

    try {
      // Update metadata modified time
      _metadata!.touch();

      // Save content
      await _ndfService.saveDocumentContent(widget.filePath, _content!);

      // Update metadata
      await _ndfService.updateMetadata(widget.filePath, _metadata!);

      setState(() {
        _hasChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('document_saved'))),
        );
      }
    } catch (e) {
      LogService().log('DocumentEditorPage: Error saving document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  void _startEditing(String elementId) {
    _commitEdit();

    final element = _content?.content.firstWhere(
      (e) => e.id == elementId,
      orElse: () => ParagraphElement(id: '', content: []),
    );

    if (element == null) return;

    String text = '';
    if (element is HeadingElement) {
      text = element.plainText;
    } else if (element is ParagraphElement) {
      text = element.plainText;
    } else if (element is BlockquoteElement) {
      text = element.plainText;
    } else if (element is CodeElement) {
      text = element.content;
    }

    _editController.text = text;
    setState(() {
      _editingElementId = elementId;
    });

    _editFocusNode.requestFocus();
  }

  void _commitEdit() {
    if (_editingElementId == null || _content == null) return;

    final elementIndex = _content!.content.indexWhere(
      (e) => e.id == _editingElementId,
    );
    if (elementIndex < 0) return;

    final element = _content!.content[elementIndex];
    final text = _editController.text;

    // Update element based on type
    if (element is HeadingElement) {
      _content!.content[elementIndex] = HeadingElement(
        id: element.id,
        level: element.level,
        content: _parseTextToSpans(text),
      );
    } else if (element is ParagraphElement) {
      _content!.content[elementIndex] = ParagraphElement(
        id: element.id,
        content: _parseTextToSpans(text),
      );
    } else if (element is BlockquoteElement) {
      _content!.content[elementIndex] = BlockquoteElement(
        id: element.id,
        content: _parseTextToSpans(text),
      );
    } else if (element is CodeElement) {
      _content!.content[elementIndex] = CodeElement(
        id: element.id,
        content: text,
        language: element.language,
      );
    }

    setState(() {
      _editingElementId = null;
      _hasChanges = true;
    });
  }

  List<RichTextSpan> _parseTextToSpans(String text) {
    // Simple implementation - create a single span
    // In a full implementation, this would parse markdown-like formatting
    final marks = <TextMark>{};
    if (_isBold) marks.add(TextMark.bold);
    if (_isItalic) marks.add(TextMark.italic);
    if (_isUnderline) marks.add(TextMark.underline);

    return [RichTextSpan(value: text, marks: marks)];
  }

  void _addElement(DocumentElementType type) {
    if (_content == null) return;

    final id = 'elem-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    DocumentElement newElement;

    switch (type) {
      case DocumentElementType.heading:
        newElement = HeadingElement(
          id: id,
          level: 2,
          content: [RichTextSpan(value: 'New Heading')],
        );
        break;
      case DocumentElementType.paragraph:
        newElement = ParagraphElement(
          id: id,
          content: [RichTextSpan(value: '')],
        );
        break;
      case DocumentElementType.list:
        newElement = ListElement(
          id: id,
          ordered: false,
          items: [ListItem(content: [RichTextSpan(value: 'Item 1')])],
        );
        break;
      case DocumentElementType.code:
        newElement = CodeElement(
          id: id,
          content: '',
        );
        break;
      case DocumentElementType.blockquote:
        newElement = BlockquoteElement(
          id: id,
          content: [RichTextSpan(value: '')],
        );
        break;
      case DocumentElementType.horizontalRule:
        newElement = HorizontalRuleElement(id: id);
        break;
      default:
        return;
    }

    setState(() {
      _content!.content.add(newElement);
      _hasChanges = true;
    });

    // Start editing the new element
    if (type != DocumentElementType.horizontalRule) {
      _startEditing(id);
    }
  }

  void _deleteElement(String elementId) {
    if (_content == null) return;

    setState(() {
      _content!.content.removeWhere((e) => e.id == elementId);
      if (_editingElementId == elementId) {
        _editingElementId = null;
      }
      _hasChanges = true;
    });
  }

  void _moveElement(String elementId, int direction) {
    if (_content == null) return;

    final index = _content!.content.indexWhere((e) => e.id == elementId);
    if (index < 0) return;

    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _content!.content.length) return;

    setState(() {
      final element = _content!.content.removeAt(index);
      _content!.content.insert(newIndex, element);
      _hasChanges = true;
    });
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('unsaved_changes')),
        content: Text(_i18n.t('unsaved_changes_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_i18n.t('discard')),
          ),
          FilledButton(
            onPressed: () async {
              await _save();
              if (mounted) Navigator.pop(context, true);
            },
            child: Text(_i18n.t('save')),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_metadata?.title ?? widget.title ?? _i18n.t('work_document')),
          actions: [
            if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _save,
                tooltip: _i18n.t('save'),
              ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddElementMenu,
              tooltip: _i18n.t('add_element'),
            ),
          ],
        ),
        body: Column(
          children: [
            // Formatting toolbar (when editing)
            if (_editingElementId != null)
              _buildFormattingToolbar(theme),
            // Content
            Expanded(child: _buildBody(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormattingToolbar(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _buildFormatButton(
            icon: Icons.format_bold,
            isActive: _isBold,
            onPressed: () => setState(() => _isBold = !_isBold),
          ),
          _buildFormatButton(
            icon: Icons.format_italic,
            isActive: _isItalic,
            onPressed: () => setState(() => _isItalic = !_isItalic),
          ),
          _buildFormatButton(
            icon: Icons.format_underlined,
            isActive: _isUnderline,
            onPressed: () => setState(() => _isUnderline = !_isUnderline),
          ),
          const VerticalDivider(width: 16),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _commitEdit,
            tooltip: _i18n.t('done'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _editingElementId = null),
            tooltip: _i18n.t('cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: isActive
            ? theme.colorScheme.primaryContainer
            : null,
      ),
    );
  }

  void _showAddElementMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.title),
              title: Text(_i18n.t('heading')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.heading);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(_i18n.t('paragraph')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.paragraph);
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: Text(_i18n.t('list')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.list);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(_i18n.t('code_block')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.code);
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: Text(_i18n.t('blockquote')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.blockquote);
              },
            ),
            ListTile(
              leading: const Icon(Icons.horizontal_rule),
              title: Text(_i18n.t('horizontal_rule')),
              onTap: () {
                Navigator.pop(context);
                _addElement(DocumentElementType.horizontalRule);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_i18n.t('error_loading_document')),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadDocument,
              icon: const Icon(Icons.refresh),
              label: Text(_i18n.t('retry')),
            ),
          ],
        ),
      );
    }

    if (_content == null || _content!.content.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(_i18n.t('empty_document')),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddElementMenu,
              icon: const Icon(Icons.add),
              label: Text(_i18n.t('add_content')),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _content!.content.length,
      itemBuilder: (context, index) {
        final element = _content!.content[index];
        return _buildEditableElement(element, theme);
      },
    );
  }

  Widget _buildEditableElement(DocumentElement element, ThemeData theme) {
    final isEditing = _editingElementId == element.id;

    return Stack(
      children: [
        if (isEditing)
          _buildEditingWidget(element, theme)
        else
          GestureDetector(
            onTap: () => _startEditing(element.id),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DocumentElementWidget(element: element),
            ),
          ),
        // Action buttons on hover/focus
        if (!isEditing)
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  onPressed: () => _moveElement(element.id, -1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  onPressed: () => _moveElement(element.id, 1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                  onPressed: () => _deleteElement(element.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditingWidget(DocumentElement element, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.primary,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _editController,
        focusNode: _editFocusNode,
        maxLines: element is CodeElement ? 10 : null,
        style: _getEditingStyle(element, theme),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: _getHintText(element),
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) => _commitEdit(),
      ),
    );
  }

  TextStyle? _getEditingStyle(DocumentElement element, ThemeData theme) {
    if (element is HeadingElement) {
      switch (element.level) {
        case 1:
          return theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold);
        case 2:
          return theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);
        case 3:
          return theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold);
        default:
          return theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);
      }
    }
    if (element is CodeElement) {
      return theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    }
    if (element is BlockquoteElement) {
      return theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic);
    }
    return theme.textTheme.bodyMedium;
  }

  String _getHintText(DocumentElement element) {
    if (element is HeadingElement) return _i18n.t('enter_heading');
    if (element is ParagraphElement) return _i18n.t('enter_text');
    if (element is CodeElement) return _i18n.t('enter_code');
    if (element is BlockquoteElement) return _i18n.t('enter_quote');
    return _i18n.t('enter_text');
  }
}
