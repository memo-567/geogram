/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/qr_code.dart';
import '../services/app_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_storage.dart';
import '../services/qr_code_service.dart';
import 'qr_detail_page.dart';
import 'qr_generator_page.dart';
import 'qr_scanner_page.dart';

/// QR Codes browser page with tabs for created and scanned codes
class QrBrowserPage extends StatefulWidget {
  final String appPath;
  final String appTitle;

  const QrBrowserPage({
    super.key,
    required this.appPath,
    required this.appTitle,
  });

  @override
  State<QrBrowserPage> createState() => _QrBrowserPageState();
}

class _QrBrowserPageState extends State<QrBrowserPage>
    with SingleTickerProviderStateMixin {
  final QrCodeService _qrService = QrCodeService();
  final I18nService _i18n = I18nService();
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;

  List<QrCode> _createdCodes = [];
  List<QrCode> _scannedCodes = [];
  List<QrCode> _filteredCreated = [];
  List<QrCode> _filteredScanned = [];
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_filterCodes);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Set up storage
    final profileStorage = AppService().profileStorage;
    if (profileStorage != null) {
      final scopedStorage = ScopedProfileStorage.fromAbsolutePath(
        profileStorage,
        widget.appPath,
      );
      _qrService.setStorage(scopedStorage);
    } else {
      _qrService.setStorage(FilesystemProfileStorage(widget.appPath));
    }

    await _qrService.initializeApp(widget.appPath);
    await _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() => _isLoading = true);

    try {
      final created = await _qrService.loadQrCodes(source: QrCodeSource.created);
      final scanned = await _qrService.loadQrCodes(source: QrCodeSource.scanned);

      setState(() {
        _createdCodes = created;
        _scannedCodes = scanned;
        _filterCodes();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading codes: $e')),
        );
      }
    }
  }

  void _filterCodes() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredCreated = _createdCodes;
        _filteredScanned = _scannedCodes;
      } else {
        _filteredCreated = _createdCodes.where((code) {
          return code.name.toLowerCase().contains(query) ||
              code.content.toLowerCase().contains(query) ||
              code.tags.any((t) => t.toLowerCase().contains(query));
        }).toList();

        _filteredScanned = _scannedCodes.where((code) {
          return code.name.toLowerCase().contains(query) ||
              code.content.toLowerCase().contains(query) ||
              code.tags.any((t) => t.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<QrCode>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (result != null) {
      // Save the scanned code
      final saved = await _qrService.saveQrCode(result);
      await _loadCodes();

      // Navigate to detail page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrDetailPage(
              code: saved,
              onUpdated: _loadCodes,
              onDeleted: _loadCodes,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openGenerator() async {
    final result = await Navigator.push<QrCode>(
      context,
      MaterialPageRoute(builder: (_) => const QrGeneratorPage()),
    );

    if (result != null) {
      // Save the generated code
      final saved = await _qrService.saveQrCode(result);
      await _loadCodes();

      // Navigate to detail page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrDetailPage(
              code: saved,
              onUpdated: _loadCodes,
              onDeleted: _loadCodes,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openDetail(QrCode code) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrDetailPage(
          code: code,
          onUpdated: _loadCodes,
          onDeleted: _loadCodes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _i18n.t('search_codes'),
                  border: InputBorder.none,
                ),
              )
            : Text(widget.appTitle),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
            tooltip: _isSearching ? _i18n.t('cancel') : _i18n.t('search'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.qr_code),
              text: '${_i18n.t('created')} (${_filteredCreated.length})',
            ),
            Tab(
              icon: const Icon(Icons.qr_code_scanner),
              text: '${_i18n.t('scanned')} (${_filteredScanned.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCodeList(_filteredCreated, QrCodeSource.created),
                _buildCodeList(_filteredScanned, QrCodeSource.scanned),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scan',
            onPressed: _openScanner,
            tooltip: _i18n.t('scan_code'),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: _openGenerator,
            tooltip: _i18n.t('create_code'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeList(List<QrCode> codes, QrCodeSource source) {
    if (codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              source == QrCodeSource.created
                  ? Icons.qr_code
                  : Icons.qr_code_scanner,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              source == QrCodeSource.created
                  ? _i18n.t('no_created_codes')
                  : _i18n.t('no_scanned_codes'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              source == QrCodeSource.created
                  ? _i18n.t('tap_plus_to_create')
                  : _i18n.t('tap_scan_to_start'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    // Group codes by category
    final grouped = <String?, List<QrCode>>{};
    for (final code in codes) {
      grouped.putIfAbsent(code.category, () => []).add(code);
    }

    // Sort: null category first (root), then alphabetically
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return a.compareTo(b);
      });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final category = sortedKeys[index];
        final categoryCodes = grouped[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (category != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      category,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${categoryCodes.length})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
            ...categoryCodes.map((code) => _buildCodeTile(code)),
          ],
        );
      },
    );
  }

  Widget _buildCodeTile(QrCode code) {
    final theme = Theme.of(context);

    return ListTile(
      leading: _buildCodeThumbnail(code),
      title: Text(
        code.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code.format.displayName,
            style: theme.textTheme.bodySmall,
          ),
          if (code.contentType != QrContentType.text)
            Row(
              children: [
                Icon(
                  _getContentTypeIcon(code.contentType),
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  code.contentType.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
        ],
      ),
      trailing: Text(
        _formatDate(code.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => _openDetail(code),
    );
  }

  Widget _buildCodeThumbnail(QrCode code) {
    // Decode base64 image
    try {
      final dataUri = code.image;
      if (dataUri.startsWith('data:image/')) {
        final base64Start = dataUri.indexOf(',') + 1;
        final base64Data = dataUri.substring(base64Start);
        final bytes = base64Decode(base64Data);

        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
            ),
          ),
        );
      }
    } catch (e) {
      // Fall through to placeholder
    }

    // Placeholder
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        code.format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  IconData _getContentTypeIcon(QrContentType type) {
    switch (type) {
      case QrContentType.wifi:
        return Icons.wifi;
      case QrContentType.url:
        return Icons.link;
      case QrContentType.vcard:
      case QrContentType.mecard:
        return Icons.contact_page;
      case QrContentType.email:
        return Icons.email;
      case QrContentType.phone:
        return Icons.phone;
      case QrContentType.sms:
        return Icons.sms;
      case QrContentType.geo:
        return Icons.place;
      case QrContentType.text:
        return Icons.text_fields;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
