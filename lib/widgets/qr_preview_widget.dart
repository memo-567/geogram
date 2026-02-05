/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:qr_flutter/qr_flutter.dart' hide QrCode;
import '../models/qr_code.dart';
import '../services/barcode_encoder_service.dart';

/// Shared widget for displaying QR code previews with customizations
class QrPreviewWidget extends StatelessWidget {
  final QrCode code;
  final double size;
  final bool showShadow;
  final bool showContainer;

  const QrPreviewWidget({
    super.key,
    required this.code,
    this.size = 48,
    this.showShadow = false,
    this.showContainer = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget qrContent = _buildQrContent(context);

    if (!showContainer) {
      return qrContent;
    }

    return Container(
      width: size,
      height: code.format.is1D ? size / 2 : size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(showShadow ? 16 : 4),
        border: showShadow
            ? null
            : Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: showShadow ? const EdgeInsets.all(16) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(showShadow ? 12 : 3),
        child: qrContent,
      ),
    );
  }

  Widget _buildQrContent(BuildContext context) {
    // For created codes with stored PNG image, use the stored image (preserves visual customizations)
    if (code.source == QrCodeSource.created && code.image.startsWith('data:image/png')) {
      try {
        final base64Start = code.image.indexOf(',') + 1;
        final base64Data = code.image.substring(base64Start);
        final bytes = base64Decode(base64Data);

        return Image.memory(
          Uint8List.fromList(bytes),
          width: size,
          height: code.format.is1D ? size / 2 : size,
          fit: BoxFit.contain,
        );
      } catch (e) {
        // Fall through to regeneration
      }
    }

    // For QR codes, use qr_flutter with customizations
    if (code.format == QrFormat.qrStandard || code.format == QrFormat.qrMicro) {
      // Parse customization colors
      final fgColor = code.foregroundColor != null
          ? Color(int.parse(code.foregroundColor!, radix: 16))
          : Colors.black;
      final bgColor = code.backgroundColor != null
          ? Color(int.parse(code.backgroundColor!, radix: 16))
          : Colors.white;
      final rounded = code.roundedModules ?? false;

      // Decode logo if present
      Uint8List? logoBytes;
      if (code.logoImage != null) {
        try {
          logoBytes = base64Decode(code.logoImage!);
        } catch (e) {
          // Ignore invalid logo data
        }
      }

      return Container(
        color: bgColor,
        child: QrImageView(
          data: code.content,
          version: QrVersions.auto,
          size: size,
          backgroundColor: bgColor,
          padding: EdgeInsets.all(size * 0.04),
          eyeStyle: QrEyeStyle(
            eyeShape: rounded ? QrEyeShape.circle : QrEyeShape.square,
            color: fgColor,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: rounded ? QrDataModuleShape.circle : QrDataModuleShape.square,
            color: fgColor,
          ),
          embeddedImage: logoBytes != null ? MemoryImage(logoBytes) : null,
          embeddedImageStyle: QrEmbeddedImageStyle(
            size: Size(size * 0.2, size * 0.2),
          ),
        ),
      );
    }

    // For other 2D codes and 1D barcodes, use flutter_zxing
    final pngBytes = BarcodeEncoderService.encodeToImage(
      content: code.content,
      format: _getZxingFormat(code.format),
      width: size.toInt(),
      height: code.format.is1D ? (size / 2).toInt() : size.toInt(),
      margin: 2,
    );

    if (pngBytes != null) {
      return Container(
        color: Colors.white,
        child: Image.memory(
          pngBytes,
          width: size,
          height: code.format.is1D ? size / 2 : size,
          fit: BoxFit.contain,
        ),
      );
    }

    // Placeholder fallback if encoding fails
    return Container(
      width: size,
      height: code.format.is1D ? size / 2 : size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        code.format.is2D ? Icons.qr_code_2 : Icons.barcode_reader,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  int _getZxingFormat(QrFormat format) {
    switch (format) {
      case QrFormat.qrStandard:
      case QrFormat.qrMicro:
        return Format.qrCode;
      case QrFormat.dataMatrix:
        return Format.dataMatrix;
      case QrFormat.aztec:
        return Format.aztec;
      case QrFormat.pdf417:
        return Format.pdf417;
      case QrFormat.maxicode:
        return Format.maxiCode;
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
    }
  }
}
