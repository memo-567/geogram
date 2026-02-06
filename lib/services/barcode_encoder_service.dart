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

      final data = result.data!;

      // Derive actual dimensions from data length
      // Some formats may return different dimensions than requested
      int imgWidth = width;
      int imgHeight = actualHeight;

      if (data.length == width * actualHeight) {
        // Exact match — use as-is
      } else if (width > 0 && data.length % width == 0) {
        imgHeight = data.length ~/ width;
      } else if (actualHeight > 0 && data.length % actualHeight == 0) {
        imgWidth = data.length ~/ actualHeight;
      } else {
        return null;
      }

      // flutter_zxing returns grayscale bytes (1 byte per pixel, luminance)
      // Create RGB image from grayscale data
      final image = img.Image(width: imgWidth, height: imgHeight);

      for (int y = 0; y < imgHeight; y++) {
        for (int x = 0; x < imgWidth; x++) {
          final lum = data[y * imgWidth + x];
          // Set pixel as RGB with same value for R, G, B (grayscale)
          image.setPixelRgb(x, y, lum, lum, lum);
        }
      }

      return Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      return null;
    }
  }

  /// Add notes text below an existing PNG image
  ///
  /// [fontSize] selects the bitmap font: 14 (small), 24 (medium), 48 (large).
  /// [bold] simulates bold by drawing text with a 1px horizontal offset.
  /// Returns new PNG bytes with notes drawn below the original image.
  static Uint8List addNotesToImage(
    Uint8List pngBytes,
    String notes, {
    int fontSize = 14,
    bool bold = false,
  }) {
    final original = img.decodePng(pngBytes);
    if (original == null) return pngBytes;

    // Select font based on requested size
    final img.BitmapFont font;
    final int charWidth; // approximate character width for centering
    switch (fontSize) {
      case 48:
        font = img.arial48;
        charWidth = 26;
        break;
      case 24:
        font = img.arial24;
        charWidth = 13;
        break;
      default:
        font = img.arial14;
        charWidth = 8;
        break;
    }

    final textHeight = fontSize + 16;
    final newImage = img.Image(
      width: original.width,
      height: original.height + textHeight,
    );

    // Fill background white
    img.fill(newImage, color: img.ColorRgb8(255, 255, 255));

    // Composite original image at top
    img.compositeImage(newImage, original, dstX: 0, dstY: 0);

    // Draw notes text centered below
    final maxChars = (original.width ~/ charWidth).clamp(10, 80);
    final truncated = notes.length > maxChars
        ? '${notes.substring(0, maxChars - 3)}...'
        : notes;
    final textWidth = truncated.length * charWidth;
    final textX = (original.width - textWidth) ~/ 2;
    final textY = original.height + 8;
    final color = img.ColorRgb8(0, 0, 0);

    img.drawString(
      newImage,
      truncated,
      font: font,
      x: textX.clamp(4, original.width - 4),
      y: textY,
      color: color,
    );

    // Simulate bold by drawing again with 1px offset
    if (bold) {
      img.drawString(
        newImage,
        truncated,
        font: font,
        x: (textX + 1).clamp(4, original.width - 4),
        y: textY,
        color: color,
      );
    }

    return Uint8List.fromList(img.encodePng(newImage));
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
