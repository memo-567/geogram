/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/websnapshot_content.dart';
import '../services/ndf_service.dart';
import '../services/web_snapshot_service.dart';
import '../widgets/websnapshot/snapshot_card_widget.dart';
import '../widgets/websnapshot/capture_progress_widget.dart';

/// Web snapshot editor page
class WebSnapshotEditorPage extends StatefulWidget {
  final String filePath;
  final String? title;

  const WebSnapshotEditorPage({
    super.key,
    required this.filePath,
    this.title,
  });

  @override
  State<WebSnapshotEditorPage> createState() => _WebSnapshotEditorPageState();
}

class _WebSnapshotEditorPageState extends State<WebSnapshotEditorPage> {
  final I18nService _i18n = I18nService();
  final NdfService _ndfService = NdfService();
  final WebSnapshotService _snapshotService = WebSnapshotService();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _urlController = TextEditingController();

  NdfDocument? _metadata;
  WebSnapshotContent? _content;
  List<WebSnapshot> _snapshots = [];
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _isCapturing = false;
  CaptureProgress? _captureProgress;
  String? _error;
  CrawlDepth _selectedDepth = CrawlDepth.single;
  StreamSubscription<CaptureProgress>? _captureSubscription;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _captureSubscription?.cancel();
    _snapshotService.dispose();
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final metadata = await _ndfService.readMetadata(widget.filePath);
      if (metadata == null) {
        throw Exception('Could not read document metadata');
      }

      final content = await _ndfService.readWebSnapshotContent(widget.filePath);
      if (content == null) {
        throw Exception('Could not read web snapshot content');
      }

      final snapshots = await _ndfService.readWebSnapshots(
        widget.filePath,
        content.snapshots,
      );

      setState(() {
        _metadata = metadata;
        _content = content;
        _snapshots = snapshots;
        _selectedDepth = content.settings.defaultDepth;
        _urlController.text = content.targetUrl;
        _isLoading = false;
      });
    } catch (e) {
      LogService().log('WebSnapshotEditorPage: Error loading document: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_content == null || _metadata == null) return;

    try {
      _metadata!.touch();
      _content!.touch();

      await _ndfService.saveWebSnapshotContent(widget.filePath, _content!);
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
      LogService().log('WebSnapshotEditorPage: Error saving document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  Future<void> _startCapture() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('work_websnapshot_url_required'))),
      );
      return;
    }

    // Update target URL in content
    if (_content != null && _content!.targetUrl != url) {
      _content!.targetUrl = url;
      _hasChanges = true;
    }

    // Create new snapshot
    final snapshot = WebSnapshot.create(
      url: url,
      depth: _selectedDepth,
    );
    snapshot.status = CrawlStatus.crawling;

    setState(() {
      _isCapturing = true;
      _captureProgress = null;
    });

    // Capture website
    final stream = _snapshotService.captureWebsite(
      url: url,
      depth: _selectedDepth,
      settings: _content?.settings ?? WebSnapshotSettings(),
      snapshot: snapshot,
      saveAsset: (path, data) async {
        await _ndfService.saveSnapshotAssets(
          widget.filePath,
          snapshot.id,
          {path: data},
        );
      },
    );

    _captureSubscription = stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _captureProgress = progress;
          });
        }
      },
      onDone: () async {
        if (mounted) {
          // Save snapshot metadata
          await _ndfService.saveWebSnapshot(widget.filePath, snapshot);

          // Update content
          _content?.addSnapshot(snapshot.id);
          await _ndfService.saveWebSnapshotContent(widget.filePath, _content!);

          setState(() {
            _snapshots.add(snapshot);
            _isCapturing = false;
            _captureProgress = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('work_websnapshot_complete'))),
          );
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isCapturing = false;
            _captureProgress = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Capture failed: $error')),
          );
        }
      },
    );
  }

  void _cancelCapture() {
    _snapshotService.cancel();
    _captureSubscription?.cancel();
    setState(() {
      _isCapturing = false;
      _captureProgress = null;
    });
  }

  Future<void> _deleteSnapshot(WebSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('work_websnapshot_delete_snapshot')),
        content: Text(_i18n.t('work_websnapshot_delete_confirm')
            .replaceAll('{date}', _formatDate(snapshot.capturedAt))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(_i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _ndfService.deleteWebSnapshot(widget.filePath, snapshot.id);
      _content?.removeSnapshot(snapshot.id);
      await _ndfService.saveWebSnapshotContent(widget.filePath, _content!);

      setState(() {
        _snapshots.removeWhere((s) => s.id == snapshot.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('work_websnapshot_deleted'))),
        );
      }
    } catch (e) {
      LogService().log('WebSnapshotEditorPage: Error deleting snapshot: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e')),
        );
      }
    }
  }

  Future<void> _viewSnapshot(WebSnapshot snapshot) async {
    // Extract snapshot to temp directory and open in browser
    final tempDir = await _ndfService.extractSnapshotToTemp(
      widget.filePath,
      snapshot.id,
    );

    if (tempDir == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('work_websnapshot_view_error'))),
        );
      }
      return;
    }

    // Show dialog with info about viewing
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_i18n.t('work_websnapshot_view')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_i18n.t('work_websnapshot_extracted_to')),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  '$tempDir/index.html',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _i18n.t('work_websnapshot_open_browser_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_i18n.t('ok')),
            ),
          ],
        ),
      );
    }
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyS) {
        _save();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _renameDocument() async {
    if (_content == null) return;

    final controller = TextEditingController(text: _content!.title);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('work_websnapshot_rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _i18n.t('title'),
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_i18n.t('save')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != _content!.title) {
      setState(() {
        _content!.title = result;
        if (_metadata != null) {
          _metadata!.title = result;
        }
        _hasChanges = true;
      });
    }
  }

  void _showSettings() async {
    if (_content == null) return;

    final settings = _content!.settings;
    var defaultDepth = settings.defaultDepth;
    var includeScripts = settings.includeScripts;
    var includeStyles = settings.includeStyles;
    var includeImages = settings.includeImages;
    var includeFonts = settings.includeFonts;
    var maxAssetSizeMb = settings.maxAssetSizeMb;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(_i18n.t('work_websnapshot_settings')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<CrawlDepth>(
                    initialValue: defaultDepth,
                    decoration: InputDecoration(
                      labelText: _i18n.t('work_websnapshot_default_depth'),
                      border: const OutlineInputBorder(),
                    ),
                    items: CrawlDepth.values.map((depth) {
                      return DropdownMenuItem(
                        value: depth,
                        child: Text(_getDepthLabel(depth)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => defaultDepth = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_i18n.t('work_websnapshot_include_scripts')),
                    value: includeScripts,
                    onChanged: (val) => setDialogState(() => includeScripts = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_i18n.t('work_websnapshot_include_styles')),
                    value: includeStyles,
                    onChanged: (val) => setDialogState(() => includeStyles = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_i18n.t('work_websnapshot_include_images')),
                    value: includeImages,
                    onChanged: (val) => setDialogState(() => includeImages = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_i18n.t('work_websnapshot_include_fonts')),
                    value: includeFonts,
                    onChanged: (val) => setDialogState(() => includeFonts = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_i18n.t('work_websnapshot_max_asset_size')),
                      ),
                      DropdownButton<int>(
                        value: maxAssetSizeMb,
                        items: [5, 10, 20, 50].map((size) {
                          return DropdownMenuItem(
                            value: size,
                            child: Text('$size MB'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => maxAssetSizeMb = val);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_i18n.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_i18n.t('save')),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      setState(() {
        _content!.settings = WebSnapshotSettings(
          defaultDepth: defaultDepth,
          includeScripts: includeScripts,
          includeStyles: includeStyles,
          includeImages: includeImages,
          includeFonts: includeFonts,
          maxAssetSizeMb: maxAssetSizeMb,
        );
        _selectedDepth = defaultDepth;
        _hasChanges = true;
      });
    }
  }

  String _getDepthLabel(CrawlDepth depth) {
    switch (depth) {
      case CrawlDepth.single:
        return _i18n.t('work_websnapshot_depth_single');
      case CrawlDepth.one:
        return _i18n.t('work_websnapshot_depth_one');
      case CrawlDepth.two:
        return _i18n.t('work_websnapshot_depth_two');
      case CrawlDepth.three:
        return _i18n.t('work_websnapshot_depth_three');
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: PopScope(
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
            title: GestureDetector(
              onTap: _renameDocument,
              child: Text(_content?.title ?? widget.title ?? _i18n.t('work_websnapshot')),
            ),
            actions: [
              if (_hasChanges)
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                  tooltip: _i18n.t('save'),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _handleMenuAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined),
                        const SizedBox(width: 8),
                        Text(_i18n.t('work_websnapshot_rename')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings_outlined),
                        const SizedBox(width: 8),
                        Text(_i18n.t('work_websnapshot_settings')),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'rename':
        _renameDocument();
        break;
      case 'settings':
        _showSettings();
        break;
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final theme = Theme.of(context);
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
        // URL input section
        _buildUrlInput(),

        // Capture progress
        if (_isCapturing && _captureProgress != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: CaptureProgressWidget(
              progress: _captureProgress!,
              onCancel: _cancelCapture,
            ),
          ),

        // Snapshots list
        Expanded(child: _buildSnapshotsList()),
      ],
    );
  }

  Widget _buildUrlInput() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !_isCapturing,
                  decoration: InputDecoration(
                    hintText: _i18n.t('work_websnapshot_url_hint'),
                    prefixIcon: const Icon(Icons.language),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _startCapture(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isCapturing ? null : _startCapture,
                icon: const Icon(Icons.download),
                label: Text(_i18n.t('work_websnapshot_capture')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _i18n.t('work_websnapshot_depth'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(width: 12),
              SegmentedButton<CrawlDepth>(
                segments: CrawlDepth.values.map((depth) {
                  return ButtonSegment(
                    value: depth,
                    label: Text(_getDepthShortLabel(depth)),
                  );
                }).toList(),
                selected: {_selectedDepth},
                onSelectionChanged: _isCapturing
                    ? null
                    : (selection) {
                        setState(() {
                          _selectedDepth = selection.first;
                        });
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getDepthShortLabel(CrawlDepth depth) {
    switch (depth) {
      case CrawlDepth.single:
        return '0';
      case CrawlDepth.one:
        return '1';
      case CrawlDepth.two:
        return '2';
      case CrawlDepth.three:
        return '3';
    }
  }

  Widget _buildSnapshotsList() {
    if (_snapshots.isEmpty && !_isCapturing) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.web_asset_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(_i18n.t('work_websnapshot_no_snapshots')),
            const SizedBox(height: 8),
            Text(
              _i18n.t('work_websnapshot_add_first'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Sort snapshots by date (newest first)
    final sortedSnapshots = List<WebSnapshot>.from(_snapshots);
    sortedSnapshots.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSnapshots.length,
      itemBuilder: (context, index) {
        final snapshot = sortedSnapshots[index];
        return SnapshotCardWidget(
          key: ValueKey(snapshot.id),
          snapshot: snapshot,
          onView: () => _viewSnapshot(snapshot),
          onDelete: () => _deleteSnapshot(snapshot),
        );
      },
    );
  }
}
