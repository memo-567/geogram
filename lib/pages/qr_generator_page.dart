/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/qr_code.dart' as qr_model;
import '../services/i18n_service.dart';

/// Page for generating QR codes and barcodes
class QrGeneratorPage extends StatefulWidget {
  /// Pre-fill content (optional)
  final String? initialContent;

  /// Pre-select format (optional)
  final qr_model.QrFormat? initialFormat;

  const QrGeneratorPage({
    super.key,
    this.initialContent,
    this.initialFormat,
  });

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage>
    with SingleTickerProviderStateMixin {
  final I18nService _i18n = I18nService();
  final GlobalKey _qrKey = GlobalKey();

  late TabController _tabController;
  late TextEditingController _contentController;
  late TextEditingController _nameController;
  late TextEditingController _notesController;

  // WiFi fields
  late TextEditingController _wifiSsidController;
  late TextEditingController _wifiPasswordController;
  String _wifiAuthType = 'WPA';
  bool _wifiHidden = false;

  // Contact fields
  late TextEditingController _contactNameController;
  late TextEditingController _contactPhoneController;
  late TextEditingController _contactEmailController;

  qr_model.QrFormat _selectedFormat = qr_model.QrFormat.qrStandard;
  qr_model.QrErrorCorrection _errorCorrection = qr_model.QrErrorCorrection.m;
  String _contentType = 'text'; // text, url, wifi, contact

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);

    _contentController = TextEditingController(text: widget.initialContent);
    _nameController = TextEditingController();
    _notesController = TextEditingController();

    _wifiSsidController = TextEditingController();
    _wifiPasswordController = TextEditingController();

    _contactNameController = TextEditingController();
    _contactPhoneController = TextEditingController();
    _contactEmailController = TextEditingController();

    if (widget.initialFormat != null) {
      _selectedFormat = widget.initialFormat!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _contentController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      switch (_tabController.index) {
        case 0:
          _contentType = 'text';
          break;
        case 1:
          _contentType = 'url';
          break;
        case 2:
          _contentType = 'wifi';
          break;
        case 3:
          _contentType = 'contact';
          break;
      }
    });
  }

  String _getContent() {
    switch (_contentType) {
      case 'text':
      case 'url':
        return _contentController.text;
      case 'wifi':
        return qr_model.WifiQrContent(
          ssid: _wifiSsidController.text,
          password: _wifiPasswordController.text,
          authType: _wifiAuthType,
          hidden: _wifiHidden,
        ).toQrString();
      case 'contact':
        return _buildVCard();
      default:
        return _contentController.text;
    }
  }

  String _buildVCard() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:3.0');
    if (_contactNameController.text.isNotEmpty) {
      buffer.writeln('FN:${_contactNameController.text}');
      buffer.writeln('N:${_contactNameController.text};;;');
    }
    if (_contactPhoneController.text.isNotEmpty) {
      buffer.writeln('TEL:${_contactPhoneController.text}');
    }
    if (_contactEmailController.text.isNotEmpty) {
      buffer.writeln('EMAIL:${_contactEmailController.text}');
    }
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  String _getDefaultName() {
    switch (_contentType) {
      case 'wifi':
        return _wifiSsidController.text.isNotEmpty
            ? 'WiFi: ${_wifiSsidController.text}'
            : 'WiFi Network';
      case 'url':
        try {
          final uri = Uri.parse(_contentController.text);
          return uri.host.isNotEmpty ? uri.host : 'URL';
        } catch (e) {
          return 'URL';
        }
      case 'contact':
        return _contactNameController.text.isNotEmpty
            ? _contactNameController.text
            : 'Contact';
      case 'text':
      default:
        final text = _contentController.text;
        if (text.length <= 30) return text;
        return '${text.substring(0, 27)}...';
    }
  }

  bool _isContentValid() {
    final content = _getContent();
    return content.isNotEmpty;
  }

  Future<void> _generateAndSave() async {
    if (!_isContentValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('please_enter_content'))),
      );
      return;
    }

    final content = _getContent();
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : _getDefaultName();

    // Capture the QR code image
    final imageBase64 = await _captureQrImage();

    final code = qr_model.QrCode(
      name: name,
      format: _selectedFormat,
      content: content,
      source: qr_model.QrCodeSource.created,
      image: imageBase64,
      errorCorrection: _errorCorrection,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    );

    if (mounted) {
      Navigator.pop(context, code);
    }
  }

  Future<String> _captureQrImage() async {
    try {
      // Find the RenderRepaintBoundary
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        return _generatePlaceholderImage();
      }

      // Capture image
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return _generatePlaceholderImage();
      }

      final bytes = byteData.buffer.asUint8List();
      final base64 = base64Encode(bytes);
      return 'data:image/png;base64,$base64';
    } catch (e) {
      return _generatePlaceholderImage();
    }
  }

  String _generatePlaceholderImage() {
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('create_code')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isContentValid() ? _generateAndSave : null,
            tooltip: _i18n.t('save'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.text_fields), text: _i18n.t('text')),
            Tab(icon: const Icon(Icons.link), text: _i18n.t('url')),
            Tab(icon: const Icon(Icons.wifi), text: 'WiFi'),
            Tab(icon: const Icon(Icons.contact_page), text: _i18n.t('contact')),
          ],
        ),
      ),
      body: Column(
        children: [
          // QR Code Preview
          Container(
            padding: const EdgeInsets.all(24),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _buildQrPreview(),
                ),
              ),
            ),
          ),

          // Content input tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTextTab(),
                _buildUrlTab(),
                _buildWifiTab(),
                _buildContactTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isContentValid() ? _generateAndSave : null,
            icon: const Icon(Icons.save),
            label: Text(_i18n.t('save_code')),
          ),
        ),
      ),
    );
  }

  Widget _buildQrPreview() {
    final content = _getContent();
    if (content.isEmpty) {
      return Container(
        width: 200,
        height: 200,
        color: Colors.white,
        child: Center(
          child: Text(
            _i18n.t('enter_content_to_preview'),
            style: TextStyle(color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Only QR codes are supported by qr_flutter
    if (_selectedFormat.is2D &&
        (_selectedFormat == qr_model.QrFormat.qrStandard || _selectedFormat == qr_model.QrFormat.qrMicro)) {
      return QrImageView(
        data: content,
        version: QrVersions.auto,
        size: 200,
        backgroundColor: Colors.white,
        errorCorrectionLevel: _getQrErrorLevel(),
      );
    }

    // For other formats, show a placeholder with content
    return Container(
      width: 200,
      height: _selectedFormat.is1D ? 80 : 200,
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedFormat.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFormat.displayName,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            content.length > 30 ? '${content.substring(0, 27)}...' : content,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  int _getQrErrorLevel() {
    switch (_errorCorrection) {
      case qr_model.QrErrorCorrection.l:
        return QrErrorCorrectLevel.L;
      case qr_model.QrErrorCorrection.m:
        return QrErrorCorrectLevel.M;
      case qr_model.QrErrorCorrection.q:
        return QrErrorCorrectLevel.Q;
      case qr_model.QrErrorCorrection.h:
        return QrErrorCorrectLevel.H;
    }
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _contentController,
            decoration: InputDecoration(
              labelText: _i18n.t('content'),
              hintText: _i18n.t('enter_text'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 4,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _buildCommonFields(),
        ],
      ),
    );
  }

  Widget _buildUrlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _contentController,
            decoration: InputDecoration(
              labelText: _i18n.t('url'),
              hintText: 'https://example.com',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _buildCommonFields(),
        ],
      ),
    );
  }

  Widget _buildWifiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _wifiSsidController,
            decoration: InputDecoration(
              labelText: _i18n.t('network_name'),
              hintText: 'MyNetwork',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.wifi),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wifiPasswordController,
            decoration: InputDecoration(
              labelText: _i18n.t('password'),
              hintText: _i18n.t('optional'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
            ),
            obscureText: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _wifiAuthType,
            decoration: InputDecoration(
              labelText: _i18n.t('security'),
              border: const OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2')),
              DropdownMenuItem(value: 'WEP', child: Text('WEP')),
              DropdownMenuItem(value: 'nopass', child: Text('None (Open)')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _wifiAuthType = value);
              }
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(_i18n.t('hidden_network')),
            value: _wifiHidden,
            onChanged: (value) => setState(() => _wifiHidden = value),
          ),
          const SizedBox(height: 16),
          _buildCommonFields(),
        ],
      ),
    );
  }

  Widget _buildContactTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _contactNameController,
            decoration: InputDecoration(
              labelText: _i18n.t('name'),
              hintText: 'John Smith',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactPhoneController,
            decoration: InputDecoration(
              labelText: _i18n.t('phone'),
              hintText: '+1 555 123 4567',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactEmailController,
            decoration: InputDecoration(
              labelText: _i18n.t('email'),
              hintText: 'john@example.com',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _buildCommonFields(),
        ],
      ),
    );
  }

  Widget _buildCommonFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),

        // Name field
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: _i18n.t('name'),
            hintText: _i18n.t('optional_name'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Notes field
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: _i18n.t('notes'),
            hintText: _i18n.t('optional_notes'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // Format selector
        Text(
          _i18n.t('code_format'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFormatChip(qr_model.QrFormat.qrStandard),
            _buildFormatChip(qr_model.QrFormat.dataMatrix),
            _buildFormatChip(qr_model.QrFormat.aztec),
            _buildFormatChip(qr_model.QrFormat.barcodeCode128),
          ],
        ),
        const SizedBox(height: 16),

        // Error correction (only for QR codes)
        if (_selectedFormat == qr_model.QrFormat.qrStandard ||
            _selectedFormat == qr_model.QrFormat.qrMicro) ...[
          Text(
            _i18n.t('error_correction'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: qr_model.QrErrorCorrection.values.map((ec) {
              return ChoiceChip(
                label: Text(ec.displayName),
                selected: _errorCorrection == ec,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _errorCorrection = ec);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildFormatChip(qr_model.QrFormat format) {
    return ChoiceChip(
      label: Text(format.displayName),
      selected: _selectedFormat == format,
      avatar: Icon(
        format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
        size: 18,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFormat = format);
        }
      },
    );
  }
}
