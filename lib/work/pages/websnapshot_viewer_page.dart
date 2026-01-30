/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/i18n_service.dart';
import '../../services/log_service.dart';
import '../models/websnapshot_content.dart';
import '../services/ndf_service.dart';

/// Page for viewing a captured web snapshot in an embedded WebView
class WebSnapshotViewerPage extends StatefulWidget {
  final String filePath;
  final WebSnapshot snapshot;

  const WebSnapshotViewerPage({
    super.key,
    required this.filePath,
    required this.snapshot,
  });

  @override
  State<WebSnapshotViewerPage> createState() => _WebSnapshotViewerPageState();
}

class _WebSnapshotViewerPageState extends State<WebSnapshotViewerPage> {
  final I18nService _i18n = I18nService();
  final NdfService _ndfService = NdfService();

  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  String? _extractedPath;
  String _currentTitle = '';
  double _loadingProgress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _extractAndLoad();
  }

  @override
  void dispose() {
    // Clean up extracted files
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    if (_extractedPath != null) {
      try {
        final dir = Directory(_extractedPath!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          LogService().log('WebSnapshotViewerPage: Cleaned up temp files');
        }
      } catch (e) {
        LogService().log('WebSnapshotViewerPage: Error cleaning temp files: $e');
      }
    }
  }

  Future<void> _extractAndLoad() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Extract snapshot to temp directory
      final tempDir = await _ndfService.extractSnapshotToTemp(
        widget.filePath,
        widget.snapshot.id,
      );

      if (tempDir == null) {
        throw Exception('Failed to extract snapshot');
      }

      _extractedPath = tempDir;
      final indexPath = '$tempDir/index.html';
      final indexFile = File(indexPath);

      if (!await indexFile.exists()) {
        throw Exception('index.html not found in snapshot');
      }

      // Initialize WebView controller
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              setState(() {
                _isLoading = true;
              });
            },
            onProgress: (progress) {
              setState(() {
                _loadingProgress = progress / 100.0;
              });
            },
            onPageFinished: (url) async {
              setState(() {
                _isLoading = false;
              });
              await _updateNavigationState();
            },
            onWebResourceError: (error) {
              LogService().log('WebSnapshotViewerPage: Web error: ${error.description}');
            },
            onNavigationRequest: (request) {
              // Allow navigation within local files
              if (request.url.startsWith('file://')) {
                return NavigationDecision.navigate;
              }
              // Block external URLs - we're viewing offline content
              LogService().log('WebSnapshotViewerPage: Blocked external URL: ${request.url}');
              return NavigationDecision.prevent;
            },
          ),
        );

      // Load the local HTML file
      await controller.loadFile(indexPath);

      // Get page title
      final title = await controller.getTitle();

      setState(() {
        _controller = controller;
        _currentTitle = title ?? widget.snapshot.title ?? '';
        _isLoading = false;
      });
    } catch (e) {
      LogService().log('WebSnapshotViewerPage: Error loading snapshot: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateNavigationState() async {
    if (_controller != null) {
      final canGoBack = await _controller!.canGoBack();
      final canGoForward = await _controller!.canGoForward();
      final title = await _controller!.getTitle();

      if (mounted) {
        setState(() {
          _canGoBack = canGoBack;
          _canGoForward = canGoForward;
          if (title != null && title.isNotEmpty) {
            _currentTitle = title;
          }
        });
      }
    }
  }

  Future<void> _goBack() async {
    if (_controller != null && _canGoBack) {
      await _controller!.goBack();
      await _updateNavigationState();
    }
  }

  Future<void> _goForward() async {
    if (_controller != null && _canGoForward) {
      await _controller!.goForward();
      await _updateNavigationState();
    }
  }

  Future<void> _reload() async {
    if (_controller != null) {
      await _controller!.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentTitle.isNotEmpty
                  ? _currentTitle
                  : widget.snapshot.title ?? _i18n.t('work_websnapshot_view'),
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.snapshot.url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Navigation buttons
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack ? _goBack : null,
            tooltip: _i18n.t('work_websnapshot_back'),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? _goForward : null,
            tooltip: _i18n.t('work_websnapshot_forward'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _controller != null ? _reload : null,
            tooltip: _i18n.t('work_websnapshot_reload'),
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                ),
              )
            : null,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _i18n.t('work_websnapshot_view_error'),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _extractAndLoad,
                icon: const Icon(Icons.refresh),
                label: Text(_i18n.t('retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return WebViewWidget(controller: _controller!);
  }
}
