/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as path;

/// Document viewer type options.
enum DocumentViewerType {
  text,      // .txt, .log, plain text
  markdown,  // .md files
  pdf,       // .pdf files
  cbz,       // .cbz manga (future)
  auto,      // Detect from file extension
}

/// Reusable document viewer/editor page.
///
/// Displays documents based on file extension or explicit viewer type.
/// Supports continuous vertical scrolling for all content types.
class DocumentViewerEditorPage extends StatefulWidget {
  /// Path to the document file.
  final String filePath;

  /// Force a specific viewer type (default: auto-detect from extension).
  final DocumentViewerType viewerType;

  /// Custom title for the app bar (default: filename).
  final String? title;

  /// Read-only mode (default: true).
  final bool readOnly;

  const DocumentViewerEditorPage({
    super.key,
    required this.filePath,
    this.viewerType = DocumentViewerType.auto,
    this.title,
    this.readOnly = true,
  });

  @override
  State<DocumentViewerEditorPage> createState() => _DocumentViewerEditorPageState();
}

class _DocumentViewerEditorPageState extends State<DocumentViewerEditorPage> {
  DocumentViewerType _resolvedType = DocumentViewerType.text;
  String? _textContent;
  List<Uint8List> _pdfPages = [];
  bool _isLoading = true;
  String? _error;
  PdfDocument? _pdfDocument;

  String get _filename => path.basename(widget.filePath);

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _pdfDocument?.close();
    super.dispose();
  }

  /// Detect viewer type from file extension.
  DocumentViewerType _detectType(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return DocumentViewerType.pdf;
      case 'md':
      case 'markdown':
        return DocumentViewerType.markdown;
      case 'cbz':
        return DocumentViewerType.cbz;
      case 'txt':
      case 'log':
      case 'json':
      case 'xml':
      case 'csv':
      case 'yaml':
      case 'yml':
      case 'html':
      case 'htm':
      case 'css':
      case 'js':
      case 'dart':
      case 'py':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'sh':
      case 'bat':
      case 'ini':
      case 'conf':
      case 'cfg':
      default:
        return DocumentViewerType.text;
    }
  }

  /// Load the document content based on type.
  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Resolve viewer type
      _resolvedType = widget.viewerType == DocumentViewerType.auto
          ? _detectType(widget.filePath)
          : widget.viewerType;

      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw Exception('File not found: ${widget.filePath}');
      }

      switch (_resolvedType) {
        case DocumentViewerType.pdf:
          await _loadPdf(file);
          break;
        case DocumentViewerType.cbz:
          // Future implementation
          throw Exception('CBZ viewer not yet implemented');
        case DocumentViewerType.text:
        case DocumentViewerType.markdown:
        case DocumentViewerType.auto:
          _textContent = await file.readAsString();
          break;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Load PDF and render all pages as images.
  Future<void> _loadPdf(File file) async {
    _pdfDocument = await PdfDocument.openFile(file.path);
    final pageCount = _pdfDocument!.pagesCount;
    final pages = <Uint8List>[];

    for (int i = 1; i <= pageCount; i++) {
      final page = await _pdfDocument!.getPage(i);
      final pageImage = await page.render(
        width: page.width * 2, // 2x for better quality
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );
      await page.close();

      if (pageImage != null) {
        pages.add(pageImage.bytes);
      }
    }

    _pdfPages = pages;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? _filename),
        actions: [
          if (_resolvedType == DocumentViewerType.pdf && _pdfPages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  '${_pdfPages.length} pages',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadDocument,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildViewer();
  }

  Widget _buildViewer() {
    switch (_resolvedType) {
      case DocumentViewerType.pdf:
        return _buildPdfViewer();
      case DocumentViewerType.markdown:
        return _buildMarkdownViewer();
      case DocumentViewerType.text:
      case DocumentViewerType.cbz:
      case DocumentViewerType.auto:
      default:
        return _buildTextViewer();
    }
  }

  /// Build PDF viewer with continuous vertical scroll.
  Widget _buildPdfViewer() {
    if (_pdfPages.isEmpty) {
      return const Center(child: Text('No pages found'));
    }

    return SingleChildScrollView(
      child: Column(
        children: _pdfPages.asMap().entries.map((entry) {
          final index = entry.key;
          final pageBytes = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                // Page image
                Image.memory(
                  pageBytes,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                    );
                  },
                ),
                // Page number
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Page ${index + 1} of ${_pdfPages.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build markdown viewer.
  Widget _buildMarkdownViewer() {
    final theme = Theme.of(context);

    return Markdown(
      data: _textContent ?? '',
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        h1: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        p: theme.textTheme.bodyMedium,
        blockquote: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// Build plain text viewer.
  Widget _buildTextViewer() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _textContent ?? '',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}
