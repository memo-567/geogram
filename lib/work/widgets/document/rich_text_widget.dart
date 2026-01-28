/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../models/document_content.dart';

/// Widget for rendering rich text spans
class RichTextSpanWidget extends StatelessWidget {
  final List<RichTextSpan> spans;
  final TextStyle? baseStyle;
  final TextAlign? textAlign;

  const RichTextSpanWidget({
    super.key,
    required this.spans,
    this.baseStyle,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = baseStyle ?? theme.textTheme.bodyMedium;

    return RichText(
      textAlign: textAlign ?? TextAlign.start,
      text: TextSpan(
        style: defaultStyle,
        children: spans.map((span) => _buildSpan(span, defaultStyle)).toList(),
      ),
    );
  }

  InlineSpan _buildSpan(RichTextSpan span, TextStyle? baseStyle) {
    var style = baseStyle ?? const TextStyle();

    // Apply marks
    if (span.isBold) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }
    if (span.isItalic) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (span.isUnderline) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    if (span.isStrikethrough) {
      style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (span.isCode) {
      style = style.copyWith(
        fontFamily: 'monospace',
        backgroundColor: Colors.grey.withValues(alpha: 0.2),
      );
    }

    // Apply attributes
    if (span.color != null) {
      final color = _parseColor(span.color!);
      if (color != null) {
        style = style.copyWith(color: color);
      }
    }
    if (span.background != null) {
      final color = _parseColor(span.background!);
      if (color != null) {
        style = style.copyWith(backgroundColor: color);
      }
    }
    if (span.fontSize != null) {
      style = style.copyWith(fontSize: span.fontSize!.toDouble());
    }

    // Handle links
    if (span.link != null) {
      style = style.copyWith(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      );
    }

    return WidgetSpan(
      child: Text(span.value, style: style),
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
    );
  }

  Color? _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      final hex = colorStr.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    return null;
  }
}

/// Widget for rendering a document element
class DocumentElementWidget extends StatelessWidget {
  final DocumentElement element;
  final VoidCallback? onTap;
  final bool isEditing;
  final Widget? editingWidget;

  const DocumentElementWidget({
    super.key,
    required this.element,
    this.onTap,
    this.isEditing = false,
    this.editingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isEditing && editingWidget != null) {
      return editingWidget!;
    }

    return GestureDetector(
      onTap: onTap,
      child: _buildElement(theme),
    );
  }

  Widget _buildElement(ThemeData theme) {
    switch (element.type) {
      case DocumentElementType.heading:
        return _buildHeading(element as HeadingElement, theme);
      case DocumentElementType.paragraph:
        return _buildParagraph(element as ParagraphElement, theme);
      case DocumentElementType.list:
        return _buildList(element as ListElement, theme);
      case DocumentElementType.image:
        return _buildImage(element as ImageElement, theme);
      case DocumentElementType.table:
        return _buildTable(element as TableElement, theme);
      case DocumentElementType.code:
        return _buildCode(element as CodeElement, theme);
      case DocumentElementType.blockquote:
        return _buildBlockquote(element as BlockquoteElement, theme);
      case DocumentElementType.horizontalRule:
        return _buildHorizontalRule(theme);
      case DocumentElementType.formEmbed:
        return _buildFormEmbed(element as FormEmbedElement, theme);
    }
  }

  Widget _buildHeading(HeadingElement heading, ThemeData theme) {
    final style = _getHeadingStyle(heading.level, theme);
    return Padding(
      padding: EdgeInsets.only(
        top: heading.level <= 2 ? 24 : 16,
        bottom: 8,
      ),
      child: RichTextSpanWidget(
        spans: heading.content,
        baseStyle: style,
      ),
    );
  }

  TextStyle _getHeadingStyle(int level, ThemeData theme) {
    switch (level) {
      case 1:
        return theme.textTheme.headlineLarge!.copyWith(fontWeight: FontWeight.bold);
      case 2:
        return theme.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.bold);
      case 3:
        return theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.bold);
      case 4:
        return theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold);
      case 5:
        return theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);
      default:
        return theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.bold);
    }
  }

  Widget _buildParagraph(ParagraphElement paragraph, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RichTextSpanWidget(
        spans: paragraph.content,
        baseStyle: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildList(ListElement list, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list.items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildListItem(item, index, list.ordered, theme);
        }).toList(),
      ),
    );
  }

  Widget _buildListItem(ListItem item, int index, bool ordered, ThemeData theme) {
    final marker = ordered ? '${index + 1}.' : '\u2022';

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              marker,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichTextSpanWidget(
                  spans: item.content,
                  baseStyle: theme.textTheme.bodyMedium,
                ),
                if (item.children != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildNestedList(item.children!, theme),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNestedList(DocumentList list, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.items.asMap().entries.map((entry) {
        return _buildListItem(entry.value, entry.key, list.ordered, theme);
      }).toList(),
    );
  }

  Widget _buildImage(ImageElement image, ThemeData theme) {
    // For asset references, we'd need to load from NDF archive
    // For now, show placeholder for asset:// refs
    Widget imageWidget;

    if (image.isAsset) {
      imageWidget = Container(
        width: image.width?.toDouble() ?? 200,
        height: image.height?.toDouble() ?? 150,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              image.assetPath ?? 'Image',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      // External URL
      imageWidget = Image.network(
        image.src,
        width: image.width?.toDouble(),
        height: image.height?.toDouble(),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 150,
            color: theme.colorScheme.errorContainer,
            child: Icon(
              Icons.broken_image,
              color: theme.colorScheme.onErrorContainer,
            ),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imageWidget,
          if (image.caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                image.caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(TableElement table, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: table.rows.map((row) {
            return TableRow(
              decoration: row.header
                  ? BoxDecoration(color: theme.colorScheme.surfaceContainerHighest)
                  : null,
              children: row.cells.map((cell) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: RichTextSpanWidget(
                    spans: cell.content,
                    baseStyle: row.header
                        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                        : theme.textTheme.bodyMedium,
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCode(CodeElement code, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (code.language != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  code.language!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SelectableText(
              code.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockquote(BlockquoteElement quote, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: RichTextSpanWidget(
          spans: quote.content,
          baseStyle: theme.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalRule(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(color: theme.colorScheme.outlineVariant),
    );
  }

  Widget _buildFormEmbed(FormEmbedElement embed, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.assignment, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Embedded Form',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    embed.formRef,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying a full document
class DocumentContentWidget extends StatelessWidget {
  final DocumentContent content;
  final String? editingElementId;
  final ValueChanged<String>? onElementTap;
  final Widget Function(DocumentElement element)? editingWidgetBuilder;

  const DocumentContentWidget({
    super.key,
    required this.content,
    this.editingElementId,
    this.onElementTap,
    this.editingWidgetBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: content.content.length,
      itemBuilder: (context, index) {
        final element = content.content[index];
        return DocumentElementWidget(
          key: ValueKey(element.id),
          element: element,
          isEditing: editingElementId == element.id,
          editingWidget: editingElementId == element.id && editingWidgetBuilder != null
              ? editingWidgetBuilder!(element)
              : null,
          onTap: onElementTap != null ? () => onElementTap!(element.id) : null,
        );
      },
    );
  }
}
