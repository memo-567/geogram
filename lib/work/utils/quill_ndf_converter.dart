/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../models/document_content.dart';

/// Converter between Quill Delta format and NDF RichTextSpan format
class QuillNdfConverter {
  int _elementCounter = 1;

  /// Generate a unique element ID
  String _generateId() {
    return 'el-${(_elementCounter++).toString().padLeft(3, '0')}';
  }

  /// Convert NDF DocumentContent to Quill Document
  Document ndfToQuill(DocumentContent content) {
    final ops = <Operation>[];

    for (final element in content.content) {
      _convertElementToOps(element, ops);
    }

    // Ensure document ends with newline
    if (ops.isEmpty ||
        (ops.last.data is String && !(ops.last.data as String).endsWith('\n'))) {
      ops.add(Operation.insert('\n'));
    }

    return Document.fromDelta(Delta.fromOperations(ops));
  }

  /// Convert a single NDF element to Quill operations
  void _convertElementToOps(DocumentElement element, List<Operation> ops) {
    if (element is HeadingElement) {
      _convertSpansToOps(element.content, ops);
      ops.add(Operation.insert('\n', {'header': element.level}));
    } else if (element is ParagraphElement) {
      _convertSpansToOps(element.content, ops);
      ops.add(Operation.insert('\n'));
    } else if (element is BlockquoteElement) {
      _convertSpansToOps(element.content, ops);
      ops.add(Operation.insert('\n', {'blockquote': true}));
    } else if (element is CodeElement) {
      // Code blocks: insert content line by line with code-block attribute
      final lines = element.content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].isNotEmpty) {
          ops.add(Operation.insert(lines[i]));
        }
        ops.add(Operation.insert('\n', {'code-block': element.language ?? true}));
      }
    } else if (element is ListElement) {
      _convertListToOps(element, ops);
    } else if (element is HorizontalRuleElement) {
      // Insert horizontal rule as an embed
      ops.add(Operation.insert({'divider': true}));
      ops.add(Operation.insert('\n'));
    } else if (element is ImageElement) {
      // Insert image as an embed
      ops.add(Operation.insert({'image': element.src}));
      ops.add(Operation.insert('\n'));
    }
  }

  /// Convert list element to Quill operations
  void _convertListToOps(ListElement list, List<Operation> ops) {
    final listType = list.ordered ? 'ordered' : 'bullet';
    for (final item in list.items) {
      _convertSpansToOps(item.content, ops);
      ops.add(Operation.insert('\n', {'list': listType}));
      // Handle nested lists
      if (item.children != null) {
        _convertNestedListToOps(item.children!, ops, 1);
      }
    }
  }

  /// Convert nested list with indent
  void _convertNestedListToOps(DocumentList list, List<Operation> ops, int indent) {
    final listType = list.ordered ? 'ordered' : 'bullet';
    for (final item in list.items) {
      _convertSpansToOps(item.content, ops);
      ops.add(Operation.insert('\n', {'list': listType, 'indent': indent}));
      if (item.children != null) {
        _convertNestedListToOps(item.children!, ops, indent + 1);
      }
    }
  }

  /// Convert RichTextSpans to Quill operations
  void _convertSpansToOps(List<RichTextSpan> spans, List<Operation> ops) {
    for (final span in spans) {
      if (span.value.isEmpty) continue;
      final attrs = _marksToAttributes(span);
      if (attrs.isEmpty) {
        ops.add(Operation.insert(span.value));
      } else {
        ops.add(Operation.insert(span.value, attrs));
      }
    }
  }

  /// Convert NDF marks to Quill attributes
  Map<String, dynamic> _marksToAttributes(RichTextSpan span) {
    final attrs = <String, dynamic>{};

    // Text marks
    if (span.marks.contains(TextMark.bold)) {
      attrs['bold'] = true;
    }
    if (span.marks.contains(TextMark.italic)) {
      attrs['italic'] = true;
    }
    if (span.marks.contains(TextMark.underline)) {
      attrs['underline'] = true;
    }
    if (span.marks.contains(TextMark.strikethrough)) {
      attrs['strike'] = true;
    }
    if (span.marks.contains(TextMark.code)) {
      attrs['code'] = true;
    }

    // Attrs from NDF
    if (span.link != null) {
      attrs['link'] = span.link;
    }
    if (span.color != null) {
      attrs['color'] = span.color;
    }
    if (span.background != null) {
      attrs['background'] = span.background;
    }

    return attrs;
  }

  /// Convert Quill Document to NDF DocumentContent
  DocumentContent quillToNdf(Document doc, {PageStyles? styles}) {
    _elementCounter = 1;
    final elements = <DocumentElement>[];
    var currentSpans = <RichTextSpan>[];
    var currentCodeLines = <String>[];
    String? codeLanguage;
    bool inCodeBlock = false;

    for (final op in doc.toDelta().operations) {
      if (!op.isInsert) continue;

      final data = op.data;
      final attrs = op.attributes ?? {};

      // Handle embeds (images, dividers)
      if (data is Map) {
        // Flush any pending spans
        if (currentSpans.isNotEmpty) {
          elements.add(ParagraphElement(
            id: _generateId(),
            content: currentSpans,
          ));
          currentSpans = [];
        }

        if (data.containsKey('divider')) {
          elements.add(HorizontalRuleElement(id: _generateId()));
        } else if (data.containsKey('image')) {
          elements.add(ImageElement(
            id: _generateId(),
            src: data['image'] as String,
          ));
        }
        continue;
      }

      final text = data as String;

      if (text == '\n') {
        // End of block - determine element type from attributes
        if (attrs.containsKey('code-block')) {
          // Code block line
          if (!inCodeBlock) {
            inCodeBlock = true;
            codeLanguage = attrs['code-block'] is String
                ? attrs['code-block'] as String
                : null;
          }
          // Add accumulated text as code line
          final lineText = currentSpans.map((s) => s.value).join();
          currentCodeLines.add(lineText);
          currentSpans = [];
        } else {
          // End of code block if we were in one
          if (inCodeBlock) {
            elements.add(CodeElement(
              id: _generateId(),
              content: currentCodeLines.join('\n'),
              language: codeLanguage,
            ));
            currentCodeLines = [];
            inCodeBlock = false;
            codeLanguage = null;
          }

          final element = _createElementFromBlock(
            spans: currentSpans,
            blockAttrs: attrs,
          );
          if (element != null) {
            elements.add(element);
          }
          currentSpans = [];
        }
      } else {
        // Inline text - split by newlines for proper handling
        final lines = text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].isNotEmpty) {
            currentSpans.add(RichTextSpan(
              value: lines[i],
              marks: _attributesToMarks(attrs),
              attrs: _attributesToNdfAttrs(attrs),
            ));
          }
          // If not the last segment, this is an embedded newline
          if (i < lines.length - 1) {
            if (currentSpans.isNotEmpty) {
              elements.add(ParagraphElement(
                id: _generateId(),
                content: currentSpans,
              ));
              currentSpans = [];
            }
          }
        }
      }
    }

    // Flush remaining code block
    if (inCodeBlock && currentCodeLines.isNotEmpty) {
      elements.add(CodeElement(
        id: _generateId(),
        content: currentCodeLines.join('\n'),
        language: codeLanguage,
      ));
    }

    // Flush remaining spans
    if (currentSpans.isNotEmpty) {
      elements.add(ParagraphElement(
        id: _generateId(),
        content: currentSpans,
      ));
    }

    return DocumentContent(
      content: elements.isEmpty
          ? [ParagraphElement(id: _generateId(), content: [RichTextSpan(value: '')])]
          : elements,
      styles: styles,
    );
  }

  /// Create a NDF element from block attributes
  DocumentElement? _createElementFromBlock({
    required List<RichTextSpan> spans,
    required Map<String, dynamic> blockAttrs,
  }) {
    // Heading
    if (blockAttrs.containsKey('header')) {
      final level = blockAttrs['header'] as int;
      return HeadingElement(
        id: _generateId(),
        level: level.clamp(1, 6),
        content: spans.isEmpty ? [RichTextSpan(value: '')] : spans,
      );
    }

    // Blockquote
    if (blockAttrs.containsKey('blockquote')) {
      return BlockquoteElement(
        id: _generateId(),
        content: spans.isEmpty ? [RichTextSpan(value: '')] : spans,
      );
    }

    // List - handled separately in a more complex way
    if (blockAttrs.containsKey('list')) {
      final listType = blockAttrs['list'] as String;
      return ListElement(
        id: _generateId(),
        ordered: listType == 'ordered',
        items: [ListItem(content: spans.isEmpty ? [RichTextSpan(value: '')] : spans)],
      );
    }

    // Default to paragraph
    if (spans.isEmpty) return null;
    return ParagraphElement(
      id: _generateId(),
      content: spans,
    );
  }

  /// Convert Quill attributes to NDF text marks
  Set<TextMark> _attributesToMarks(Map<String, dynamic> attrs) {
    final marks = <TextMark>{};

    if (attrs['bold'] == true) {
      marks.add(TextMark.bold);
    }
    if (attrs['italic'] == true) {
      marks.add(TextMark.italic);
    }
    if (attrs['underline'] == true) {
      marks.add(TextMark.underline);
    }
    if (attrs['strike'] == true) {
      marks.add(TextMark.strikethrough);
    }
    if (attrs['code'] == true) {
      marks.add(TextMark.code);
    }

    return marks;
  }

  /// Convert Quill attributes to NDF attrs map
  Map<String, dynamic>? _attributesToNdfAttrs(Map<String, dynamic> attrs) {
    final ndfAttrs = <String, dynamic>{};

    if (attrs.containsKey('link')) {
      ndfAttrs['link'] = attrs['link'];
    }
    if (attrs.containsKey('color')) {
      ndfAttrs['color'] = attrs['color'];
    }
    if (attrs.containsKey('background')) {
      ndfAttrs['background'] = attrs['background'];
    }

    return ndfAttrs.isEmpty ? null : ndfAttrs;
  }

  /// Merge consecutive list elements of the same type
  List<DocumentElement> mergeConsecutiveLists(List<DocumentElement> elements) {
    if (elements.isEmpty) return elements;

    final merged = <DocumentElement>[];
    ListElement? currentList;

    for (final element in elements) {
      if (element is ListElement) {
        if (currentList != null && currentList.ordered == element.ordered) {
          // Merge into current list
          currentList = ListElement(
            id: currentList.id,
            ordered: currentList.ordered,
            items: [...currentList.items, ...element.items],
          );
        } else {
          // Start new list
          if (currentList != null) {
            merged.add(currentList);
          }
          currentList = element;
        }
      } else {
        // Flush current list
        if (currentList != null) {
          merged.add(currentList);
          currentList = null;
        }
        merged.add(element);
      }
    }

    // Flush remaining list
    if (currentList != null) {
      merged.add(currentList);
    }

    return merged;
  }
}
