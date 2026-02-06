/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/qr_code.dart';
import '../services/i18n_service.dart';
import '../services/qr_code_service.dart';
import '../widgets/qr_preview_widget.dart';
import 'photo_viewer_page.dart';
import 'qr_generator_page.dart';

/// Page for viewing and editing QR code details
class QrDetailPage extends StatefulWidget {
  final QrCode code;
  final VoidCallback? onUpdated;
  final VoidCallback? onDeleted;

  const QrDetailPage({
    super.key,
    required this.code,
    this.onUpdated,
    this.onDeleted,
  });

  @override
  State<QrDetailPage> createState() => _QrDetailPageState();
}

class _QrDetailPageState extends State<QrDetailPage> {
  final I18nService _i18n = I18nService();
  final QrCodeService _qrService = QrCodeService();

  late QrCode _code;

  @override
  void initState() {
    super.initState();
    _code = widget.code;
  }

  Future<void> _deleteCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('delete_code')),
        content: Text(_i18n.t('delete_code_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && _code.filePath != null) {
      try {
        await _qrService.deleteQrCode(_code.filePath!);
        widget.onDeleted?.call();
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _showMoveToFolderDialog() async {
    final folders = await _qrService.getSubfolders(_code.source);

    if (!mounted) return;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('move_to_folder')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "No folder" option (root)
              ListTile(
                leading: const Icon(Icons.folder_off),
                title: Text(_i18n.t('no_folder')),
                selected: _code.category == null,
                onTap: () => Navigator.pop(context, ''),
              ),
              // Existing folders
              ...folders.map((folder) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folder),
                    selected: _code.category == folder,
                    onTap: () => Navigator.pop(context, folder),
                  )),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      final targetFolder = result.isEmpty ? null : result;
      if (targetFolder != _code.category) {
        final movedCode = await _qrService.moveQrCode(_code, targetFolder);
        setState(() {
          _code = movedCode;
        });
        widget.onUpdated?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('code_moved'))),
          );
        }
      }
    }
  }

  Future<void> _copyContent() async {
    await Clipboard.setData(ClipboardData(text: _code.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('copied_to_clipboard', params: ['Content']))),
      );
    }
  }

  Future<void> _openGeneratorForEdit() async {
    final result = await Navigator.push<QrCode>(
      context,
      MaterialPageRoute(
        builder: (_) => QrGeneratorPage(editCode: _code),
      ),
    );

    if (result != null) {
      try {
        // Update the code with the edited version
        final updated = await _qrService.updateQrCode(result);
        setState(() {
          _code = updated;
        });
        widget.onUpdated?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('saved'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving: $e')),
          );
        }
      }
    }
  }

  Future<void> _shareCode() async {
    try {
      // Decode image from base64
      if (_code.image.startsWith('data:image/')) {
        final base64Start = _code.image.indexOf(',') + 1;
        final base64Data = _code.image.substring(base64Start);
        final bytes = base64Decode(base64Data);

        // Save to temp file
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/${_code.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.png');
        await file.writeAsBytes(bytes);

        // Share
        await Share.shareXFiles(
          [XFile(file.path)],
          text: _code.name,
        );
      } else {
        // Share content as text
        await Share.share(_code.content, subject: _code.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  Future<void> _openContent() async {
    final content = _code.content;
    Uri? uri;

    switch (_code.contentType) {
      case QrContentType.url:
        uri = Uri.tryParse(content);
        break;
      case QrContentType.email:
        if (content.toLowerCase().startsWith('mailto:')) {
          uri = Uri.tryParse(content);
        } else {
          uri = Uri(scheme: 'mailto', path: content);
        }
        break;
      case QrContentType.phone:
        if (content.toLowerCase().startsWith('tel:')) {
          uri = Uri.tryParse(content);
        } else {
          uri = Uri(scheme: 'tel', path: content);
        }
        break;
      case QrContentType.sms:
        if (content.toLowerCase().startsWith('sms:') ||
            content.toLowerCase().startsWith('smsto:')) {
          uri = Uri.tryParse(content.replaceFirst('smsto:', 'sms:'));
        }
        break;
      case QrContentType.geo:
        uri = Uri.tryParse(content);
        break;
      default:
        break;
    }

    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _showFullscreen(BuildContext context) async {
    try {
      // Decode the stored image and write to a temp file
      if (!_code.image.startsWith('data:image/')) return;
      final base64Start = _code.image.indexOf(',') + 1;
      final base64Data = _code.image.substring(base64Start);
      final bytes = base64Decode(base64Data);

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_fullscreen_${_code.id}.png');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(imagePaths: [file.path]),
        ),
      );
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_code.name),
        actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _openGeneratorForEdit,
              tooltip: _i18n.t('edit'),
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareCode,
              tooltip: _i18n.t('share'),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'copy':
                    _copyContent();
                    break;
                  case 'move':
                    _showMoveToFolderDialog();
                    break;
                  case 'delete':
                    _deleteCode();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: const Icon(Icons.copy),
                    title: Text(_i18n.t('copy_content')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_move),
                    title: Text(_i18n.t('move_to_folder')),
                    subtitle: _code.category != null
                        ? Text(_code.category!)
                        : Text(_i18n.t('no_folder')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: Text(
                      _i18n.t('delete'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code image with notes underneath
            Container(
              padding: const EdgeInsets.all(24),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrPreviewWidget(
                    code: _code,
                    size: 200,
                    showShadow: true,
                  ),
                  // Fullscreen button
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen),
                      tooltip: _i18n.t('fullscreen'),
                      onPressed: () => _showFullscreen(context),
                    ),
                  ),
                ],
              ),
            ),

            // Content section
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildDetailView(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _code.contentType != QrContentType.text &&
              _code.contentType != QrContentType.wifi
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _openContent,
                  icon: Icon(_getActionIcon()),
                  label: Text(_getActionLabel()),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildDetailView() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Format and type chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(_code.format.displayName),
              avatar: Icon(
                _code.format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
                size: 18,
              ),
            ),
            Chip(
              label: Text(_code.contentType.displayName),
              avatar: Icon(_getContentTypeIcon(), size: 18),
            ),
            Chip(
              label: Text(_code.source == QrCodeSource.created
                  ? _i18n.t('created')
                  : _i18n.t('scanned')),
              avatar: Icon(
                _code.source == QrCodeSource.created
                    ? Icons.add_circle
                    : Icons.camera_alt,
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Content
        Text(
          _i18n.t('content'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        _buildContentPreview(),
        const SizedBox(height: 16),

        // Dates
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _i18n.t('created'),
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(_formatDateTime(_code.createdAt)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _i18n.t('modified'),
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(_formatDateTime(_code.modifiedAt)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tags
        if (_code.tags.isNotEmpty) ...[
          Text(
            _i18n.t('tags'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _code.tags.map((tag) {
              return Chip(
                label: Text(tag),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // Notes are displayed inside the QR code image
      ],
    );
  }

  Widget _buildContentPreview() {
    final theme = Theme.of(context);

    // Special formatting for WiFi
    if (_code.contentType == QrContentType.wifi) {
      final wifi = WifiQrContent.parse(_code.content);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi, size: 16),
                const SizedBox(width: 8),
                Text('SSID: ${wifi.ssid}'),
              ],
            ),
            if (wifi.password != null && wifi.password!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.lock, size: 16),
                  const SizedBox(width: 8),
                  Text('Password: ${wifi.password}'),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.security, size: 16),
                const SizedBox(width: 8),
                Text('Security: ${wifi.authType}'),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        _code.content,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  IconData _getContentTypeIcon() {
    switch (_code.contentType) {
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

  IconData _getActionIcon() {
    switch (_code.contentType) {
      case QrContentType.url:
        return Icons.open_in_browser;
      case QrContentType.email:
        return Icons.email;
      case QrContentType.phone:
        return Icons.call;
      case QrContentType.sms:
        return Icons.sms;
      case QrContentType.geo:
        return Icons.map;
      default:
        return Icons.open_in_new;
    }
  }

  String _getActionLabel() {
    switch (_code.contentType) {
      case QrContentType.url:
        return _i18n.t('open_url');
      case QrContentType.email:
        return _i18n.t('send_email');
      case QrContentType.phone:
        return _i18n.t('call');
      case QrContentType.sms:
        return _i18n.t('send_sms');
      case QrContentType.geo:
        return _i18n.t('open_map');
      default:
        return _i18n.t('open');
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
