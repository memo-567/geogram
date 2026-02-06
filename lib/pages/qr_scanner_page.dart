/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/qr_code.dart';
import '../services/barcode_encoder_service.dart';
import '../services/i18n_service.dart';

/// Page for scanning QR codes and barcodes
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final I18nService _i18n = I18nService();

  bool _isScanning = false;
  bool _hasScanned = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    _startScanner();
  }

  Future<void> _startScanner() async {
    // flutter_zxing supports: Android, iOS, macOS
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      setState(() {
        _scanError = _i18n.t('camera_not_supported');
      });
      return;
    }

    final status = await Permission.camera.status;

    if (status.isGranted) {
      _initScanner();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionDenied = true;
        _permissionPermanentlyDenied = true;
      });
    } else {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        _initScanner();
      } else {
        setState(() {
          _permissionDenied = true;
          _permissionPermanentlyDenied = result.isPermanentlyDenied;
        });
      }
    }
  }

  void _initScanner() {
    setState(() {
      _isScanning = true;
      _hasScanned = false;
      _scanError = null;
    });
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
      _scanError = null;
    });
  }

  void _onScan(Code code) {
    if (_hasScanned) return;
    if (!code.isValid) return;

    final value = code.text;
    if (value == null) return;

    setState(() {
      _hasScanned = true;
    });

    _showScanResult(code);
  }

  Future<void> _showScanResult(Code code) async {
    final content = code.text ?? '';
    final format = _mapZxingFormat(code.format);
    final contentType = QrContentType.detect(content);

    // Generate image from the scanned code
    final imageBase64 = await _generateCodeImage(content, format);

    // Show confirmation dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ScanResultDialog(
        content: content,
        format: format,
        contentType: contentType,
        imageBase64: imageBase64,
        i18n: _i18n,
      ),
    );

    if (result != null && result['save'] == true) {
      // If notes were provided, embed them into the stored image
      final notes = result['notes'] as String?;
      var finalImage = imageBase64;
      if (notes != null && notes.trim().isNotEmpty && imageBase64.startsWith('data:image/png')) {
        try {
          final base64Start = imageBase64.indexOf(',') + 1;
          final base64Data = imageBase64.substring(base64Start);
          final imgBytes = base64Decode(base64Data);
          final withNotes = BarcodeEncoderService.addNotesToImage(imgBytes, notes.trim());
          finalImage = 'data:image/png;base64,${base64Encode(withNotes)}';
        } catch (e) {
          // Keep original image on error
        }
      }

      // Create QrCode object
      final qrCode = QrCode(
        name: result['name'] as String? ?? _generateDefaultName(contentType, content),
        format: format,
        content: content,
        source: QrCodeSource.scanned,
        image: finalImage,
        notes: notes,
      );

      if (mounted) {
        Navigator.pop(context, qrCode);
      }
    } else {
      _resetScanner();
    }
  }

  QrFormat _mapZxingFormat(int? format) {
    if (format == null) return QrFormat.qrStandard;

    if (format == Format.qrCode) return QrFormat.qrStandard;
    if (format == Format.dataMatrix) return QrFormat.dataMatrix;
    if (format == Format.aztec) return QrFormat.aztec;
    if (format == Format.maxiCode) return QrFormat.maxicode;
    if (format == Format.code39) return QrFormat.barcodeCode39;
    if (format == Format.code93) return QrFormat.barcodeCode93;
    if (format == Format.code128) return QrFormat.barcodeCode128;
    if (format == Format.codabar) return QrFormat.barcodeCodabar;
    if (format == Format.ean8) return QrFormat.barcodeEan8;
    if (format == Format.ean13) return QrFormat.barcodeEan13;
    if (format == Format.itf) return QrFormat.barcodeItf;
    if (format == Format.upca) return QrFormat.barcodeUpca;
    if (format == Format.upce) return QrFormat.barcodeUpce;

    return QrFormat.qrStandard;
  }

  Future<String> _generateCodeImage(String content, QrFormat format) async {
    try {
      // Use the barcode encoder service to generate a proper PNG image
      final encodeFormat = _getEncodeFormat(format);
      final pngBytes = BarcodeEncoderService.encodeToImage(
        content: content,
        format: encodeFormat,
        width: 300,
        height: format.is1D ? 100 : 300,
        margin: 10,
      );

      if (pngBytes != null) {
        final base64 = base64Encode(pngBytes);
        return 'data:image/png;base64,$base64';
      }
    } catch (e) {
      // Fall back to placeholder
    }

    // Return a placeholder - we'll regenerate proper image in generator page
    return _generatePlaceholderImage(format);
  }

  int _getEncodeFormat(QrFormat format) {
    switch (format) {
      case QrFormat.qrStandard:
      case QrFormat.qrMicro:
        return Format.qrCode;
      case QrFormat.dataMatrix:
        return Format.dataMatrix;
      case QrFormat.aztec:
        return Format.aztec;
      case QrFormat.barcodeCode39:
        return Format.code39;
      case QrFormat.barcodeCode93:
        return Format.code93;
      case QrFormat.barcodeCode128:
        return Format.code128;
      case QrFormat.barcodeCodabar:
        return Format.codabar;
      case QrFormat.barcodeEan8:
        return Format.ean8;
      case QrFormat.barcodeEan13:
        return Format.ean13;
      case QrFormat.barcodeItf:
        return Format.itf;
      case QrFormat.barcodeUpca:
        return Format.upca;
      case QrFormat.barcodeUpce:
        return Format.upce;
      default:
        return Format.qrCode;
    }
  }

  String _generatePlaceholderImage(QrFormat format) {
    // Simple 1x1 transparent PNG as fallback
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
  }

  String _generateDefaultName(QrContentType type, String content) {
    switch (type) {
      case QrContentType.wifi:
        final wifi = WifiQrContent.parse(content);
        return wifi.ssid.isNotEmpty ? 'WiFi: ${wifi.ssid}' : 'WiFi Network';
      case QrContentType.url:
        try {
          final uri = Uri.parse(content);
          return uri.host.isNotEmpty ? uri.host : 'URL';
        } catch (e) {
          return 'URL';
        }
      case QrContentType.vcard:
      case QrContentType.mecard:
        return 'Contact';
      case QrContentType.email:
        return 'Email';
      case QrContentType.phone:
        return 'Phone';
      case QrContentType.sms:
        return 'SMS';
      case QrContentType.geo:
        return 'Location';
      case QrContentType.text:
        // Truncate long text
        if (content.length <= 30) {
          return content;
        }
        return '${content.substring(0, 27)}...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('scan_code')),
        actions: [
          if (_hasScanned)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetScanner,
              tooltip: _i18n.t('scan_again'),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_scanError != null) {
      return _buildErrorView(theme, _scanError!);
    }

    if (_permissionDenied) {
      return _buildPermissionDeniedView(theme);
    }

    if (!_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_i18n.t('initializing_camera')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview
        ReaderWidget(
          onScan: _onScan,
          isMultiScan: false,
          showFlashlight: true,
          showToggleCamera: true,
          showGallery: false,
          tryHarder: true,
          tryInverted: true,
        ),

        // Scanning overlay
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Corner decorations
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: CustomPaint(
              painter: _CornersPainter(color: theme.colorScheme.primary),
            ),
          ),
        ),

        // Instructions
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _i18n.t('point_camera_at_code'),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              error,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _permissionPermanentlyDenied
                  ? _i18n.t('camera_permission_denied')
                  : _i18n.t('camera_permission_required'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_permissionPermanentlyDenied)
              FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: Text(_i18n.t('open_settings')),
              )
            else
              FilledButton.icon(
                onPressed: _startScanner,
                icon: const Icon(Icons.refresh),
                label: Text(_i18n.t('try_again')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to show scan result and get user input
class _ScanResultDialog extends StatefulWidget {
  final String content;
  final QrFormat format;
  final QrContentType contentType;
  final String imageBase64;
  final I18nService i18n;

  const _ScanResultDialog({
    required this.content,
    required this.format,
    required this.contentType,
    required this.imageBase64,
    required this.i18n,
  });

  @override
  State<_ScanResultDialog> createState() => _ScanResultDialogState();
}

class _ScanResultDialogState extends State<_ScanResultDialog> {
  late TextEditingController _nameController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _generateDefaultName(),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateDefaultName() {
    switch (widget.contentType) {
      case QrContentType.wifi:
        final wifi = WifiQrContent.parse(widget.content);
        return wifi.ssid.isNotEmpty ? 'WiFi: ${wifi.ssid}' : 'WiFi Network';
      case QrContentType.url:
        try {
          final uri = Uri.parse(widget.content);
          return uri.host.isNotEmpty ? uri.host : 'URL';
        } catch (e) {
          return 'URL';
        }
      case QrContentType.vcard:
      case QrContentType.mecard:
        return 'Contact';
      case QrContentType.email:
        return 'Email';
      case QrContentType.phone:
        return 'Phone';
      case QrContentType.sms:
        return 'SMS';
      case QrContentType.geo:
        return 'Location';
      case QrContentType.text:
        if (widget.content.length <= 30) {
          return widget.content;
        }
        return '${widget.content.substring(0, 27)}...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.qr_code_scanner, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(widget.i18n.t('code_scanned')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Code image
            Center(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: _buildCodeImage(),
              ),
            ),
            const SizedBox(height: 16),

            // Format and content type
            Row(
              children: [
                Chip(
                  label: Text(widget.format.displayName),
                  avatar: Icon(
                    widget.format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(widget.contentType.displayName),
                  avatar: Icon(
                    _getContentTypeIcon(widget.contentType),
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content preview
            Text(
              widget.i18n.t('content'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.content.length > 200
                    ? '${widget.content.substring(0, 200)}...'
                    : widget.content,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Name input
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('name'),
                hintText: widget.i18n.t('enter_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Notes input
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('notes'),
                hintText: widget.i18n.t('optional_notes'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, {'save': false}),
          child: Text(widget.i18n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, {
            'save': true,
            'name': _nameController.text.trim(),
            'notes': _notesController.text.trim(),
          }),
          icon: const Icon(Icons.save),
          label: Text(widget.i18n.t('save')),
        ),
      ],
    );
  }

  Widget _buildCodeImage() {
    try {
      if (widget.imageBase64.startsWith('data:image/')) {
        final base64Start = widget.imageBase64.indexOf(',') + 1;
        final base64Data = widget.imageBase64.substring(base64Start);
        final bytes = base64Decode(base64Data);
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
        );
      }
    } catch (e) {
      // Fall through to placeholder
    }

    return Icon(
      widget.format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
      size: 64,
      color: Colors.grey,
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
}

/// Custom painter for corner decorations
class _CornersPainter extends CustomPainter {
  final Color color;

  _CornersPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 16.0;

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(cornerLength, size.height),
      paint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
