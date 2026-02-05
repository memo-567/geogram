/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:typed_data';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;

/// Service for encoding barcodes and QR codes to PNG images
class BarcodeEncoderService {
  /// Encode content as barcode/QR and return PNG bytes
  ///
  /// Returns null if encoding fails (e.g., invalid content for format)
  static Uint8List? encodeToImage({
    required String content,
    required int format,
    int width = 300,
    int? height,
    int margin = 10,
  }) {
    try {
      final actualHeight = height ?? (is1DFormat(format) ? 100 : width);

      final result = zx.encodeBarcode(
        contents: content,
        params: EncodeParams(
          format: format,
          width: width,
          height: actualHeight,
          margin: margin,
        ),
      );

      if (!result.isValid || result.data == null) return null;

      // flutter_zxing returns raw RGBA pixels at the requested dimensions
      final image = img.Image.fromBytes(
        width: width,
        height: actualHeight,
        bytes: result.data!.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      return Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      return null;
    }
  }

  /// Check if the format is a 1D barcode
  static bool is1DFormat(int format) {
    return format == Format.code39 ||
        format == Format.code93 ||
        format == Format.code128 ||
        format == Format.codabar ||
        format == Format.ean8 ||
        format == Format.ean13 ||
        format == Format.itf ||
        format == Format.upca ||
        format == Format.upce;
  }

  /// Get the ZXing format constant from QrFormat enum
  static int getZxingFormat(String zxingFormatName) {
    switch (zxingFormatName) {
      case 'QR_CODE':
        return Format.qrCode;
      case 'DATA_MATRIX':
        return Format.dataMatrix;
      case 'AZTEC':
        return Format.aztec;
      case 'PDF_417':
        return Format.pdf417;
      case 'MAXICODE':
        return Format.maxiCode;
      case 'CODE_39':
        return Format.code39;
      case 'CODE_93':
        return Format.code93;
      case 'CODE_128':
        return Format.code128;
      case 'CODABAR':
        return Format.codabar;
      case 'EAN_8':
        return Format.ean8;
      case 'EAN_13':
        return Format.ean13;
      case 'ITF':
        return Format.itf;
      case 'UPC_A':
        return Format.upca;
      case 'UPC_E':
        return Format.upce;
      default:
        return Format.qrCode;
    }
  }
}
