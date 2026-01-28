/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Types of document elements
enum DocumentElementType {
  heading,
  paragraph,
  list,
  image,
  table,
  code,
  blockquote,
  horizontalRule,
  formEmbed,
}

/// Text marks for inline formatting
enum TextMark {
  bold,
  italic,
  underline,
  strikethrough,
  code,
  superscript,
  subscript,
}

/// A text span with optional marks
class RichTextSpan {
  final String value;
  final Set<TextMark> marks;
  final Map<String, dynamic>? attrs;

  RichTextSpan({
    required this.value,
    Set<TextMark>? marks,
    this.attrs,
  }) : marks = marks ?? {};

  factory RichTextSpan.fromJson(Map<String, dynamic> json) {
    final marksJson = json['marks'] as List<dynamic>? ?? [];
    final marks = marksJson
        .map((m) => TextMark.values.firstWhere(
              (t) => t.name == m,
              orElse: () => TextMark.bold,
            ))
        .toSet();

    return RichTextSpan(
      value: json['value'] as String? ?? '',
      marks: marks,
      attrs: json['attrs'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'text',
    'value': value,
    if (marks.isNotEmpty) 'marks': marks.map((m) => m.name).toList(),
    if (attrs != null) 'attrs': attrs,
  };

  bool get isBold => marks.contains(TextMark.bold);
  bool get isItalic => marks.contains(TextMark.italic);
  bool get isUnderline => marks.contains(TextMark.underline);
  bool get isStrikethrough => marks.contains(TextMark.strikethrough);
  bool get isCode => marks.contains(TextMark.code);

  String? get link => attrs?['link'] as String?;
  String? get color => attrs?['color'] as String?;
  String? get background => attrs?['background'] as String?;
  int? get fontSize => attrs?['font_size'] as int?;
}

/// A list item
class ListItem {
  final List<RichTextSpan> content;
  final DocumentList? children;

  ListItem({
    required this.content,
    this.children,
  });

  factory ListItem.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List<dynamic>? ?? [];
    final content = contentJson
        .map((c) => RichTextSpan.fromJson(c as Map<String, dynamic>))
        .toList();

    DocumentList? children;
    if (json['children'] != null) {
      children = DocumentList.fromJson(json['children'] as Map<String, dynamic>);
    }

    return ListItem(content: content, children: children);
  }

  Map<String, dynamic> toJson() => {
    'content': content.map((c) => c.toJson()).toList(),
    if (children != null) 'children': children!.toJson(),
  };
}

/// A list element
class DocumentList {
  final bool ordered;
  final List<ListItem> items;

  DocumentList({
    required this.ordered,
    required this.items,
  });

  factory DocumentList.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    final items = itemsJson
        .map((i) => ListItem.fromJson(i as Map<String, dynamic>))
        .toList();

    return DocumentList(
      ordered: json['ordered'] as bool? ?? false,
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
    'ordered': ordered,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

/// A table cell
class TableCell {
  final List<RichTextSpan> content;
  final int? colspan;
  final int? rowspan;

  TableCell({
    required this.content,
    this.colspan,
    this.rowspan,
  });

  factory TableCell.fromJson(Map<String, dynamic> json) {
    // Handle both simple string content and complex content
    List<RichTextSpan> content;
    if (json['content'] is String) {
      content = [RichTextSpan(value: json['content'] as String)];
    } else if (json['content'] is List) {
      content = (json['content'] as List<dynamic>)
          .map((c) => c is String
              ? RichTextSpan(value: c)
              : RichTextSpan.fromJson(c as Map<String, dynamic>))
          .toList();
    } else {
      content = [];
    }

    return TableCell(
      content: content,
      colspan: json['colspan'] as int?,
      rowspan: json['rowspan'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'content': content.length == 1 && content.first.marks.isEmpty
        ? content.first.value
        : content.map((c) => c.toJson()).toList(),
    if (colspan != null) 'colspan': colspan,
    if (rowspan != null) 'rowspan': rowspan,
  };

  String get plainText => content.map((c) => c.value).join();
}

/// A table row
class DocumentTableRow {
  final List<TableCell> cells;
  final bool header;

  DocumentTableRow({
    required this.cells,
    this.header = false,
  });

  factory DocumentTableRow.fromJson(Map<String, dynamic> json) {
    final cellsJson = json['cells'] as List<dynamic>? ?? [];
    final cells = cellsJson
        .map((c) => TableCell.fromJson(c as Map<String, dynamic>))
        .toList();

    return DocumentTableRow(
      cells: cells,
      header: json['header'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'cells': cells.map((c) => c.toJson()).toList(),
    if (header) 'header': header,
  };
}

/// Base class for document elements
abstract class DocumentElement {
  final String id;
  final DocumentElementType type;

  DocumentElement({required this.id, required this.type});

  Map<String, dynamic> toJson();

  factory DocumentElement.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = DocumentElementType.values.firstWhere(
      (t) => t.name == typeStr || _typeAliases[typeStr] == t,
      orElse: () => DocumentElementType.paragraph,
    );

    switch (type) {
      case DocumentElementType.heading:
        return HeadingElement.fromJson(json);
      case DocumentElementType.paragraph:
        return ParagraphElement.fromJson(json);
      case DocumentElementType.list:
        return ListElement.fromJson(json);
      case DocumentElementType.image:
        return ImageElement.fromJson(json);
      case DocumentElementType.table:
        return TableElement.fromJson(json);
      case DocumentElementType.code:
        return CodeElement.fromJson(json);
      case DocumentElementType.blockquote:
        return BlockquoteElement.fromJson(json);
      case DocumentElementType.horizontalRule:
        return HorizontalRuleElement.fromJson(json);
      case DocumentElementType.formEmbed:
        return FormEmbedElement.fromJson(json);
    }
  }

  static const _typeAliases = <String, DocumentElementType>{
    'hr': DocumentElementType.horizontalRule,
    'form_embed': DocumentElementType.formEmbed,
  };
}

/// Heading element (h1-h6)
class HeadingElement extends DocumentElement {
  final int level;
  final List<RichTextSpan> content;

  HeadingElement({
    required super.id,
    required this.level,
    required this.content,
  }) : super(type: DocumentElementType.heading);

  factory HeadingElement.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List<dynamic>? ?? [];
    final content = contentJson
        .map((c) => RichTextSpan.fromJson(c as Map<String, dynamic>))
        .toList();

    return HeadingElement(
      id: json['id'] as String? ?? '',
      level: json['level'] as int? ?? 1,
      content: content,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'heading',
    'id': id,
    'level': level,
    'content': content.map((c) => c.toJson()).toList(),
  };

  String get plainText => content.map((c) => c.value).join();
}

/// Paragraph element
class ParagraphElement extends DocumentElement {
  final List<RichTextSpan> content;

  ParagraphElement({
    required super.id,
    required this.content,
  }) : super(type: DocumentElementType.paragraph);

  factory ParagraphElement.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List<dynamic>? ?? [];
    final content = contentJson
        .map((c) => RichTextSpan.fromJson(c as Map<String, dynamic>))
        .toList();

    return ParagraphElement(
      id: json['id'] as String? ?? '',
      content: content,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'paragraph',
    'id': id,
    'content': content.map((c) => c.toJson()).toList(),
  };

  String get plainText => content.map((c) => c.value).join();
}

/// List element
class ListElement extends DocumentElement {
  final bool ordered;
  final List<ListItem> items;

  ListElement({
    required super.id,
    required this.ordered,
    required this.items,
  }) : super(type: DocumentElementType.list);

  factory ListElement.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    final items = itemsJson
        .map((i) => ListItem.fromJson(i as Map<String, dynamic>))
        .toList();

    return ListElement(
      id: json['id'] as String? ?? '',
      ordered: json['ordered'] as bool? ?? false,
      items: items,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'list',
    'id': id,
    'ordered': ordered,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

/// Image element
class ImageElement extends DocumentElement {
  final String src;
  final String? alt;
  final int? width;
  final int? height;
  final String? caption;

  ImageElement({
    required super.id,
    required this.src,
    this.alt,
    this.width,
    this.height,
    this.caption,
  }) : super(type: DocumentElementType.image);

  factory ImageElement.fromJson(Map<String, dynamic> json) {
    return ImageElement(
      id: json['id'] as String? ?? '',
      src: json['src'] as String? ?? '',
      alt: json['alt'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      caption: json['caption'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'id': id,
    'src': src,
    if (alt != null) 'alt': alt,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (caption != null) 'caption': caption,
  };

  /// Check if this is an asset reference
  bool get isAsset => src.startsWith('asset://');

  /// Get the asset path (without asset:// prefix)
  String? get assetPath => isAsset ? src.substring(8) : null;
}

/// Table element
class TableElement extends DocumentElement {
  final List<DocumentTableRow> rows;

  TableElement({
    required super.id,
    required this.rows,
  }) : super(type: DocumentElementType.table);

  factory TableElement.fromJson(Map<String, dynamic> json) {
    final rowsJson = json['rows'] as List<dynamic>? ?? [];
    final rows = rowsJson
        .map((r) => DocumentTableRow.fromJson(r as Map<String, dynamic>))
        .toList();

    return TableElement(
      id: json['id'] as String? ?? '',
      rows: rows,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'table',
    'id': id,
    'rows': rows.map((r) => r.toJson()).toList(),
  };
}

/// Code block element
class CodeElement extends DocumentElement {
  final String content;
  final String? language;

  CodeElement({
    required super.id,
    required this.content,
    this.language,
  }) : super(type: DocumentElementType.code);

  factory CodeElement.fromJson(Map<String, dynamic> json) {
    return CodeElement(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      language: json['language'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'code',
    'id': id,
    'content': content,
    if (language != null) 'language': language,
  };
}

/// Blockquote element
class BlockquoteElement extends DocumentElement {
  final List<RichTextSpan> content;

  BlockquoteElement({
    required super.id,
    required this.content,
  }) : super(type: DocumentElementType.blockquote);

  factory BlockquoteElement.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List<dynamic>? ?? [];
    final content = contentJson
        .map((c) => RichTextSpan.fromJson(c as Map<String, dynamic>))
        .toList();

    return BlockquoteElement(
      id: json['id'] as String? ?? '',
      content: content,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'blockquote',
    'id': id,
    'content': content.map((c) => c.toJson()).toList(),
  };

  String get plainText => content.map((c) => c.value).join();
}

/// Horizontal rule element
class HorizontalRuleElement extends DocumentElement {
  HorizontalRuleElement({required super.id})
      : super(type: DocumentElementType.horizontalRule);

  factory HorizontalRuleElement.fromJson(Map<String, dynamic> json) {
    return HorizontalRuleElement(id: json['id'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'horizontalRule',
    'id': id,
  };
}

/// Form embed element
class FormEmbedElement extends DocumentElement {
  final String formRef;
  final String display;

  FormEmbedElement({
    required super.id,
    required this.formRef,
    this.display = 'inline',
  }) : super(type: DocumentElementType.formEmbed);

  factory FormEmbedElement.fromJson(Map<String, dynamic> json) {
    return FormEmbedElement(
      id: json['id'] as String? ?? '',
      formRef: json['form_ref'] as String? ?? '',
      display: json['display'] as String? ?? 'inline',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'form_embed',
    'id': id,
    'form_ref': formRef,
    'display': display,
  };
}

/// Page styles
class PageStyles {
  final String size;
  final Map<String, int> margins;

  PageStyles({
    this.size = 'A4',
    Map<String, int>? margins,
  }) : margins = margins ?? {'top': 72, 'bottom': 72, 'left': 72, 'right': 72};

  factory PageStyles.fromJson(Map<String, dynamic> json) {
    final marginsJson = json['margins'] as Map<String, dynamic>? ?? {};
    final margins = <String, int>{};
    for (final entry in marginsJson.entries) {
      margins[entry.key] = (entry.value as num).toInt();
    }

    return PageStyles(
      size: json['size'] as String? ?? 'A4',
      margins: margins.isEmpty ? null : margins,
    );
  }

  Map<String, dynamic> toJson() => {
    'size': size,
    'margins': margins,
  };
}

/// Main document content (main.json)
class DocumentContent {
  final String schema;
  final List<DocumentElement> content;
  final PageStyles styles;

  DocumentContent({
    this.schema = 'ndf-richtext-1.0',
    required this.content,
    PageStyles? styles,
  }) : styles = styles ?? PageStyles();

  factory DocumentContent.create() {
    return DocumentContent(
      content: [
        ParagraphElement(
          id: 'p-001',
          content: [RichTextSpan(value: '')],
        ),
      ],
    );
  }

  factory DocumentContent.fromJson(Map<String, dynamic> json) {
    final contentJson = json['content'] as List<dynamic>? ?? [];
    final content = contentJson
        .map((c) => DocumentElement.fromJson(c as Map<String, dynamic>))
        .toList();

    PageStyles? styles;
    final stylesJson = json['styles'] as Map<String, dynamic>?;
    if (stylesJson != null) {
      final pageJson = stylesJson['page'] as Map<String, dynamic>?;
      if (pageJson != null) {
        styles = PageStyles.fromJson(pageJson);
      }
    }

    return DocumentContent(
      schema: json['schema'] as String? ?? 'ndf-richtext-1.0',
      content: content,
      styles: styles,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'document',
    'schema': schema,
    'content': content.map((c) => c.toJson()).toList(),
    'styles': {
      'page': styles.toJson(),
    },
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Get plain text representation
  String get plainText {
    final buffer = StringBuffer();
    for (final element in content) {
      if (element is HeadingElement) {
        buffer.writeln(element.plainText);
      } else if (element is ParagraphElement) {
        buffer.writeln(element.plainText);
      } else if (element is BlockquoteElement) {
        buffer.writeln('> ${element.plainText}');
      } else if (element is CodeElement) {
        buffer.writeln('```${element.language ?? ''}');
        buffer.writeln(element.content);
        buffer.writeln('```');
      }
    }
    return buffer.toString();
  }
}
