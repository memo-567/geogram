/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/qr_code.dart' as qr_model;
import '../services/barcode_encoder_service.dart';
import '../services/i18n_service.dart';

/// Page for generating QR codes and barcodes
class QrGeneratorPage extends StatefulWidget {
  /// Pre-fill content (optional)
  final String? initialContent;

  /// Pre-select format (optional)
  final qr_model.QrFormat? initialFormat;

  /// Code to edit (optional) - when provided, page works in edit mode
  final qr_model.QrCode? editCode;

  const QrGeneratorPage({
    super.key,
    this.initialContent,
    this.initialFormat,
    this.editCode,
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

  // Customization state
  Color _foregroundColor = Colors.black;
  Color _backgroundColor = Colors.white;
  bool _roundedModules = false;
  Uint8List? _logoBytes;
  String? _logoName;

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

    // Pre-fill fields if editing an existing code
    if (widget.editCode != null) {
      _initFromEditCode(widget.editCode!);
    }
  }

  void _initFromEditCode(qr_model.QrCode code) {
    _nameController.text = code.name;
    _notesController.text = code.notes ?? '';
    _selectedFormat = code.format;
    _errorCorrection = code.errorCorrection ?? qr_model.QrErrorCorrection.m;

    // Restore customization state
    if (code.foregroundColor != null) {
      _foregroundColor = Color(int.parse(code.foregroundColor!, radix: 16));
    }
    if (code.backgroundColor != null) {
      _backgroundColor = Color(int.parse(code.backgroundColor!, radix: 16));
    }
    _roundedModules = code.roundedModules ?? false;
    if (code.logoImage != null) {
      _logoBytes = base64Decode(code.logoImage!);
      _logoName = 'Saved logo';
    }

    // Determine content type and fill appropriate fields
    switch (code.contentType) {
      case qr_model.QrContentType.wifi:
        _contentType = 'wifi';
        _tabController.index = 2;
        final wifi = qr_model.WifiQrContent.parse(code.content);
        _wifiSsidController.text = wifi.ssid;
        _wifiPasswordController.text = wifi.password ?? '';
        _wifiAuthType = wifi.authType;
        _wifiHidden = wifi.hidden;
        break;
      case qr_model.QrContentType.vcard:
      case qr_model.QrContentType.mecard:
        _contentType = 'contact';
        _tabController.index = 3;
        _parseContactFromContent(code.content);
        break;
      case qr_model.QrContentType.url:
        _contentType = 'url';
        _tabController.index = 1;
        _contentController.text = code.content;
        break;
      default:
        _contentType = 'text';
        _tabController.index = 0;
        _contentController.text = code.content;
        break;
    }
  }

  void _parseContactFromContent(String content) {
    // Parse vCard format
    final lines = content.split('\n');
    for (final line in lines) {
      if (line.startsWith('FN:')) {
        _contactNameController.text = line.substring(3).trim();
      } else if (line.startsWith('TEL:')) {
        _contactPhoneController.text = line.substring(4).trim();
      } else if (line.startsWith('EMAIL:')) {
        _contactEmailController.text = line.substring(6).trim();
      }
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

    // Prepare customization values
    final fgColor = _foregroundColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    final bgColor = _backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    final String? logoBase64 = _logoBytes != null ? base64Encode(_logoBytes!) : null;

    final qr_model.QrCode code;
    if (widget.editCode != null) {
      // Editing existing code - preserve original metadata
      code = widget.editCode!.copyWith(
        name: name,
        format: _selectedFormat,
        content: content,
        image: imageBase64,
        errorCorrection: _errorCorrection,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        foregroundColor: fgColor,
        backgroundColor: bgColor,
        roundedModules: _roundedModules,
        logoImage: logoBase64,
      );
    } else {
      // Creating new code
      code = qr_model.QrCode(
        name: name,
        format: _selectedFormat,
        content: content,
        source: qr_model.QrCodeSource.created,
        image: imageBase64,
        errorCorrection: _errorCorrection,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        foregroundColor: fgColor,
        backgroundColor: bgColor,
        roundedModules: _roundedModules,
        logoImage: logoBase64,
      );
    }

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

    final isEditing = widget.editCode != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t(isEditing ? 'edit_code' : 'create_code')),
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
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Center(
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(12),
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
        width: 140,
        height: 140,
        color: Colors.white,
        child: Center(
          child: Text(
            _i18n.t('enter_content_to_preview'),
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // QR codes - use qr_flutter (supports customization)
    if (_selectedFormat == qr_model.QrFormat.qrStandard || _selectedFormat == qr_model.QrFormat.qrMicro) {
      return QrImageView(
        data: content,
        version: QrVersions.auto,
        size: 140,
        backgroundColor: _backgroundColor,
        errorCorrectionLevel: _getQrErrorLevel(),
        eyeStyle: QrEyeStyle(
          eyeShape: _roundedModules ? QrEyeShape.circle : QrEyeShape.square,
          color: _foregroundColor,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: _roundedModules ? QrDataModuleShape.circle : QrDataModuleShape.square,
          color: _foregroundColor,
        ),
        embeddedImage: _logoBytes != null ? MemoryImage(_logoBytes!) : null,
        embeddedImageStyle: const QrEmbeddedImageStyle(
          size: Size(30, 30),
        ),
      );
    }

    // All other formats - use flutter_zxing via BarcodeEncoderService
    final is1D = _selectedFormat.is1D;
    final previewHeight = is1D ? 70 : 140;

    final pngBytes = BarcodeEncoderService.encodeToImage(
      content: content,
      format: _getZxingFormat(_selectedFormat),
      width: 140,
      height: previewHeight,
      margin: 4,
    );

    if (pngBytes != null) {
      return Container(
        color: Colors.white,
        child: Image.memory(
          pngBytes,
          width: 140,
          height: previewHeight.toDouble(),
          fit: BoxFit.contain,
        ),
      );
    }

    // Fallback to placeholder if encoding fails
    return Container(
      width: 140,
      height: is1D ? 70 : 140,
      padding: const EdgeInsets.all(6),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _selectedFormat.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
            size: is1D ? 24 : 36,
            color: Colors.grey,
          ),
          const SizedBox(height: 2),
          Text(
            _selectedFormat.displayName,
            style: TextStyle(color: Colors.grey, fontSize: is1D ? 10 : 12),
          ),
          if (!is1D) ...[
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                content.length > 20 ? '${content.substring(0, 17)}...' : content,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _getZxingFormat(qr_model.QrFormat format) {
    switch (format) {
      case qr_model.QrFormat.qrStandard:
      case qr_model.QrFormat.qrMicro:
        return Format.qrCode;
      case qr_model.QrFormat.dataMatrix:
        return Format.dataMatrix;
      case qr_model.QrFormat.aztec:
        return Format.aztec;
      case qr_model.QrFormat.pdf417:
        return Format.pdf417;
      case qr_model.QrFormat.maxicode:
        return Format.maxiCode;
      case qr_model.QrFormat.barcodeCode39:
        return Format.code39;
      case qr_model.QrFormat.barcodeCode93:
        return Format.code93;
      case qr_model.QrFormat.barcodeCode128:
        return Format.code128;
      case qr_model.QrFormat.barcodeCodabar:
        return Format.codabar;
      case qr_model.QrFormat.barcodeEan8:
        return Format.ean8;
      case qr_model.QrFormat.barcodeEan13:
        return Format.ean13;
      case qr_model.QrFormat.barcodeItf:
        return Format.itf;
      case qr_model.QrFormat.barcodeUpca:
        return Format.upca;
      case qr_model.QrFormat.barcodeUpce:
        return Format.upce;
    }
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
            textCapitalization: TextCapitalization.sentences,
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

        // Customization section (only for QR codes)
        if (_selectedFormat == qr_model.QrFormat.qrStandard) ...[
          const Divider(),
          const SizedBox(height: 8),

          Text(_i18n.t('customization'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),

          // Foreground color
          _buildColorRow(_i18n.t('foreground_color'), _foregroundColor, (c) => setState(() => _foregroundColor = c)),

          // Background color
          _buildColorRow(_i18n.t('background_color'), _backgroundColor, (c) => setState(() => _backgroundColor = c)),

          const SizedBox(height: 8),

          // Rounded modules switch
          SwitchListTile(
            title: Text(_i18n.t('rounded_modules')),
            value: _roundedModules,
            onChanged: (v) => setState(() => _roundedModules = v),
            contentPadding: EdgeInsets.zero,
          ),

          // Logo picker
          ListTile(
            title: Text(_i18n.t('center_logo')),
            subtitle: _logoName != null ? Text(_logoName!) : null,
            contentPadding: EdgeInsets.zero,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_logoBytes != null)
                  IconButton(icon: const Icon(Icons.clear), onPressed: _clearLogo),
                IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _pickLogo),
              ],
            ),
          ),

          // Warning for low error correction with logo
          if (_logoBytes != null && _errorCorrection == qr_model.QrErrorCorrection.l)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _i18n.t('logo_low_ec_warning'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
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

  Widget _buildColorRow(String label, Color color, ValueChanged<Color> onChanged) {
    return ListTile(
      title: Text(label),
      contentPadding: EdgeInsets.zero,
      trailing: GestureDetector(
        onTap: () => _showColorPicker(color, onChanged),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Future<void> _showColorPicker(Color current, ValueChanged<Color> onChanged) async {
    Color selected = current;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('pick_color')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => selected = c,
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              onChanged(selected);
              Navigator.pop(context);
            },
            child: Text(_i18n.t('select')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 200,
      maxHeight: 200,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _logoBytes = bytes;
        _logoName = image.name;
      });
    }
  }

  void _clearLogo() {
    setState(() {
      _logoBytes = null;
      _logoName = null;
    });
  }
}
