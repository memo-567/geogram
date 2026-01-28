/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show File, Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/document_content.dart';
import '../services/ndf_service.dart';
import '../utils/quill_ndf_converter.dart';

/// Document editor page for rich text documents using flutter_quill
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
  final QuillNdfConverter _converter = QuillNdfConverter();
  final ImagePicker _imagePicker = ImagePicker();

  NdfDocument? _metadata;
  PageStyles? _pageStyles;
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _error;

  /// Cache of extracted asset paths (asset:// URL -> temp file path)
  final Map<String, String> _assetCache = {};

  late QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _quillController = QuillController.basic();
    _loadDocument();
  }

  @override
  void dispose() {
    _quillController.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
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
      final documentContent = content ?? DocumentContent.create();

      // Convert NDF to Quill document
      final quillDoc = _converter.ndfToQuill(documentContent);

      setState(() {
        _metadata = metadata;
        _pageStyles = documentContent.styles;
        _quillController = QuillController(
          document: quillDoc,
          selection: const TextSelection.collapsed(offset: 0),
        );
        _isLoading = false;
      });

      // Listen for changes
      _quillController.document.changes.listen((_) {
        if (!_hasChanges && mounted) {
          setState(() {
            _hasChanges = true;
          });
        }
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
    if (_metadata == null) return;

    try {
      // Convert Quill document to NDF
      var content = _converter.quillToNdf(
        _quillController.document,
        styles: _pageStyles,
      );

      // Merge consecutive lists
      content = DocumentContent(
        schema: content.schema,
        content: _converter.mergeConsecutiveLists(content.content),
        styles: content.styles,
      );

      // Update metadata modified time
      _metadata!.touch();

      // Save content
      await _ndfService.saveDocumentContent(widget.filePath, content);

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

  /// Pick an image and save it to the NDF archive, returning the asset:// URL
  Future<String?> _pickAndSaveImage(BuildContext context) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return null;

      // Read image bytes
      final Uint8List bytes = await pickedFile.readAsBytes();

      // Generate filename from SHA1 hash (deduplicates identical images)
      final ext = pickedFile.path.split('.').last.toLowerCase();
      final hash = sha1.convert(bytes).toString();
      final assetPath = 'images/$hash.$ext';

      // Save to NDF archive
      await _ndfService.saveAsset(widget.filePath, assetPath, bytes);

      // Mark document as having changes
      if (mounted) {
        setState(() {
          _hasChanges = true;
        });
      }

      // Return asset:// URL for quill
      return 'asset://$assetPath';
    } catch (e) {
      LogService().log('DocumentEditorPage: Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error inserting image: $e')),
        );
      }
      return null;
    }
  }

  /// Get an image provider for an asset:// URL
  Future<ImageProvider?> _getAssetImageProvider(String imageUrl) async {
    if (!imageUrl.startsWith('asset://')) {
      // Network or file image
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        return NetworkImage(imageUrl);
      } else if (!kIsWeb) {
        return FileImage(File(imageUrl));
      }
      return null;
    }

    // Check cache first
    if (_assetCache.containsKey(imageUrl)) {
      final tempPath = _assetCache[imageUrl]!;
      return FileImage(File(tempPath));
    }

    // Extract asset path from URL
    final assetPath = imageUrl.substring(8); // Remove 'asset://'

    // Extract to temp file
    final tempPath = await _ndfService.extractAssetToTemp(
      widget.filePath,
      assetPath,
    );

    if (tempPath == null) return null;

    // Cache the path
    _assetCache[imageUrl] = tempPath;

    return FileImage(File(tempPath));
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      _save();
    }
  }

  Future<void> _renameDocument() async {
    if (_metadata == null) return;

    final controller = TextEditingController(text: _metadata!.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('rename_document')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _i18n.t('document_title'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_i18n.t('rename')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _metadata!.title) {
      setState(() {
        _metadata!.title = result;
        _hasChanges = true;
      });
    }
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
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
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: _isDesktop ? _renameDocument : null,
              onLongPress: _isDesktop ? null : _renameDocument,
              child: Text(_metadata?.title ?? widget.title ?? _i18n.t('work_document')),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _hasChanges ? Icons.save : Icons.save_outlined,
                  color: _hasChanges ? null : theme.disabledColor,
                ),
                onPressed: _save,
                tooltip: '${_i18n.t('save')} (Ctrl+S)',
              ),
            ],
          ),
          body: _buildBody(theme),
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

    return Column(
      children: [
        // Toolbar
        _buildToolbar(theme),
        // Divider
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        // Editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: QuillEditor(
              controller: _quillController,
              focusNode: _editorFocusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                placeholder: _i18n.t('work_enter_text'),
                padding: const EdgeInsets.symmetric(vertical: 16),
                expands: true,
                autoFocus: false,
                embedBuilders: [
                  _NdfImageEmbedBuilder(
                    getImageProvider: _getAssetImageProvider,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      height: kDefaultToolbarSize * 1.4,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Header dropdown first
            QuillToolbarSelectHeaderStyleDropdownButton(controller: _quillController),
            const QuillToolbarDivider(Axis.horizontal),
            // Undo/Redo
            QuillToolbarHistoryButton(controller: _quillController, isUndo: true),
            QuillToolbarHistoryButton(controller: _quillController, isUndo: false),
            const QuillToolbarDivider(Axis.horizontal),
            // Text formatting
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.bold,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.italic,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.underline,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.strikeThrough,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.inlineCode,
            ),
            const QuillToolbarDivider(Axis.horizontal),
            // Lists
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.ul,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.ol,
            ),
            const QuillToolbarDivider(Axis.horizontal),
            // Block formatting
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.blockQuote,
            ),
            QuillToolbarToggleStyleButton(
              controller: _quillController,
              attribute: Attribute.codeBlock,
            ),
            const QuillToolbarDivider(Axis.horizontal),
            // Indent
            QuillToolbarIndentButton(controller: _quillController, isIncrease: true),
            QuillToolbarIndentButton(controller: _quillController, isIncrease: false),
            const QuillToolbarDivider(Axis.horizontal),
            // Link
            QuillToolbarLinkStyleButton(controller: _quillController),
            const QuillToolbarDivider(Axis.horizontal),
            // Image
            IconButton(
              icon: const Icon(Icons.image),
              tooltip: _i18n.t('work_add_image'),
              onPressed: () async {
                final imageUrl = await _pickAndSaveImage(context);
                if (imageUrl != null) {
                  final index = _quillController.selection.baseOffset;
                  _quillController.document.insert(index, BlockEmbed.image(imageUrl));
                  _quillController.updateSelection(
                    TextSelection.collapsed(offset: index + 1),
                    ChangeSource.local,
                  );
                }
              },
            ),
            const QuillToolbarDivider(Axis.horizontal),
            // Clear format
            QuillToolbarClearFormatButton(controller: _quillController),
          ],
        ),
      ),
    );
  }
}

/// Custom image embed builder that handles asset:// URLs
class _NdfImageEmbedBuilder extends EmbedBuilder {
  final Future<ImageProvider?> Function(String imageUrl) getImageProvider;

  _NdfImageEmbedBuilder({required this.getImageProvider});

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final imageUrl = embedContext.node.value.data as String;

    return FutureBuilder<ImageProvider?>(
      future: getImageProvider(imageUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 200,
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final imageProvider = snapshot.data;
        if (imageProvider == null) {
          return Container(
            width: 200,
            height: 150,
            color: Theme.of(context).colorScheme.errorContainer,
            child: Center(
              child: Icon(
                Icons.broken_image,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 200,
                height: 150,
                color: Theme.of(context).colorScheme.errorContainer,
                child: Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
