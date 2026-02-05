/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Supported QR/barcode format types
enum QrFormat {
  // 2D codes
  qrStandard('qr_standard', 'QR_CODE', 'QR Code'),
  qrMicro('qr_micro', 'QR_CODE', 'Micro QR'),
  dataMatrix('data_matrix', 'DATA_MATRIX', 'Data Matrix'),
  aztec('aztec', 'AZTEC', 'Aztec'),
  pdf417('pdf417', 'PDF_417', 'PDF417'),
  maxicode('maxicode', 'MAXICODE', 'MaxiCode'),

  // 1D barcodes
  barcodeCode39('barcode_code39', 'CODE_39', 'Code 39'),
  barcodeCode93('barcode_code93', 'CODE_93', 'Code 93'),
  barcodeCode128('barcode_code128', 'CODE_128', 'Code 128'),
  barcodeCodabar('barcode_codabar', 'CODABAR', 'Codabar'),
  barcodeEan8('barcode_ean8', 'EAN_8', 'EAN-8'),
  barcodeEan13('barcode_ean13', 'EAN_13', 'EAN-13'),
  barcodeItf('barcode_itf', 'ITF', 'ITF'),
  barcodeUpca('barcode_upca', 'UPC_A', 'UPC-A'),
  barcodeUpce('barcode_upce', 'UPC_E', 'UPC-E');

  final String codeType;
  final String zxingFormat;
  final String displayName;

  const QrFormat(this.codeType, this.zxingFormat, this.displayName);

  /// Get QrFormat from codeType string
  static QrFormat? fromCodeType(String codeType) {
    for (final format in QrFormat.values) {
      if (format.codeType == codeType) {
        return format;
      }
    }
    return null;
  }

  /// Get QrFormat from ZXing format string
  static QrFormat? fromZxingFormat(String zxingFormat) {
    for (final format in QrFormat.values) {
      if (format.zxingFormat == zxingFormat) {
        return format;
      }
    }
    return null;
  }

  /// Check if this is a 2D code
  bool get is2D => index <= QrFormat.maxicode.index;

  /// Check if this is a 1D barcode
  bool get is1D => !is2D;
}

/// Error correction level for QR codes
enum QrErrorCorrection {
  l('L', 'Low (7%)'),
  m('M', 'Medium (15%)'),
  q('Q', 'Quartile (25%)'),
  h('H', 'High (30%)');

  final String code;
  final String displayName;

  const QrErrorCorrection(this.code, this.displayName);

  static QrErrorCorrection? fromCode(String? code) {
    if (code == null) return null;
    for (final ec in QrErrorCorrection.values) {
      if (ec.code == code) return ec;
    }
    return null;
  }
}

/// Source of the QR code
enum QrCodeSource {
  created('created'),
  scanned('scanned');

  final String value;

  const QrCodeSource(this.value);

  static QrCodeSource? fromValue(String value) {
    for (final source in QrCodeSource.values) {
      if (source.value == value) return source;
    }
    return null;
  }
}

/// Detected content type of QR code
enum QrContentType {
  wifi('WiFi'),
  url('URL'),
  vcard('vCard'),
  mecard('MeCard'),
  email('Email'),
  phone('Phone'),
  sms('SMS'),
  geo('Location'),
  text('Text');

  final String displayName;

  const QrContentType(this.displayName);

  /// Detect content type from content string
  static QrContentType detect(String content) {
    final upper = content.toUpperCase();
    if (upper.startsWith('WIFI:')) return QrContentType.wifi;
    if (upper.startsWith('HTTP://') || upper.startsWith('HTTPS://')) {
      return QrContentType.url;
    }
    if (upper.startsWith('BEGIN:VCARD')) return QrContentType.vcard;
    if (upper.startsWith('MECARD:')) return QrContentType.mecard;
    if (upper.startsWith('MAILTO:')) return QrContentType.email;
    if (upper.startsWith('TEL:')) return QrContentType.phone;
    if (upper.startsWith('SMSTO:') || upper.startsWith('SMS:')) {
      return QrContentType.sms;
    }
    if (upper.startsWith('GEO:')) return QrContentType.geo;
    return QrContentType.text;
  }
}

/// Model for a stored QR code or barcode
class QrCode {
  static const String formatVersion = '1.0';

  final String id;
  final String name;
  final QrFormat format;
  final String content;
  final QrCodeSource source;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? category;
  final List<String> tags;
  final String image; // Base64 data URI
  final QrErrorCorrection? errorCorrection;
  final String? notes;
  final Map<String, dynamic>? scanLocation;
  final Map<String, dynamic>? extraMetadata;

  /// File path (set when loaded from disk)
  final String? filePath;

  QrCode({
    String? id,
    required this.name,
    required this.format,
    required this.content,
    required this.source,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.category,
    List<String>? tags,
    required this.image,
    this.errorCorrection,
    this.notes,
    this.scanLocation,
    this.extraMetadata,
    this.filePath,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now(),
        tags = tags ?? [];

  /// Get detected content type
  QrContentType get contentType => QrContentType.detect(content);

  /// Create a copy with updated fields
  QrCode copyWith({
    String? id,
    String? name,
    QrFormat? format,
    String? content,
    QrCodeSource? source,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? category,
    List<String>? tags,
    String? image,
    QrErrorCorrection? errorCorrection,
    String? notes,
    Map<String, dynamic>? scanLocation,
    Map<String, dynamic>? extraMetadata,
    String? filePath,
  }) {
    return QrCode(
      id: id ?? this.id,
      name: name ?? this.name,
      format: format ?? this.format,
      content: content ?? this.content,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
      category: category ?? this.category,
      tags: tags ?? List.from(this.tags),
      image: image ?? this.image,
      errorCorrection: errorCorrection ?? this.errorCorrection,
      notes: notes ?? this.notes,
      scanLocation: scanLocation ?? this.scanLocation,
      extraMetadata: extraMetadata ?? this.extraMetadata,
      filePath: filePath ?? this.filePath,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    final metadata = <String, dynamic>{};
    if (errorCorrection != null) {
      metadata['errorCorrection'] = errorCorrection!.code;
    }
    if (notes != null && notes!.isNotEmpty) {
      metadata['notes'] = notes;
    }
    if (scanLocation != null) {
      metadata['scanLocation'] = scanLocation;
    }
    if (extraMetadata != null) {
      metadata.addAll(extraMetadata!);
    }

    return {
      'version': formatVersion,
      'id': id,
      'name': name,
      'codeType': format.codeType,
      'format': format.zxingFormat,
      'content': content,
      'source': source.value,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      if (category != null) 'category': category,
      if (tags.isNotEmpty) 'tags': tags,
      'image': image,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// Create from JSON map
  factory QrCode.fromJson(Map<String, dynamic> json, {String? filePath}) {
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};

    // Extract known metadata fields
    final errorCorrectionCode = metadata['errorCorrection'] as String?;
    final notes = metadata['notes'] as String?;
    final scanLocation = metadata['scanLocation'] as Map<String, dynamic>?;

    // Collect extra metadata
    final extraMetadata = Map<String, dynamic>.from(metadata)
      ..remove('errorCorrection')
      ..remove('notes')
      ..remove('scanLocation');

    return QrCode(
      id: json['id'] as String,
      name: json['name'] as String,
      format: QrFormat.fromCodeType(json['codeType'] as String) ??
          QrFormat.qrStandard,
      content: json['content'] as String,
      source: QrCodeSource.fromValue(json['source'] as String) ??
          QrCodeSource.created,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      category: json['category'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      image: json['image'] as String,
      errorCorrection: QrErrorCorrection.fromCode(errorCorrectionCode),
      notes: notes,
      scanLocation: scanLocation,
      extraMetadata: extraMetadata.isNotEmpty ? extraMetadata : null,
      filePath: filePath,
    );
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory QrCode.fromJsonString(String jsonString, {String? filePath}) {
    return QrCode.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
      filePath: filePath,
    );
  }

  @override
  String toString() => 'QrCode(id: $id, name: $name, format: ${format.displayName})';
}

/// Summary model for listing QR codes (lightweight)
class QrCodeSummary {
  final String id;
  final String name;
  final QrFormat format;
  final QrCodeSource source;
  final DateTime createdAt;
  final String? category;
  final List<String> tags;
  final String filePath;
  final QrContentType contentType;

  QrCodeSummary({
    required this.id,
    required this.name,
    required this.format,
    required this.source,
    required this.createdAt,
    this.category,
    List<String>? tags,
    required this.filePath,
    required this.contentType,
  }) : tags = tags ?? [];

  /// Create summary from full QrCode
  factory QrCodeSummary.fromQrCode(QrCode code) {
    return QrCodeSummary(
      id: code.id,
      name: code.name,
      format: code.format,
      source: code.source,
      createdAt: code.createdAt,
      category: code.category,
      tags: code.tags,
      filePath: code.filePath ?? '',
      contentType: code.contentType,
    );
  }

  /// Create from JSON map (for cache)
  factory QrCodeSummary.fromJson(Map<String, dynamic> json) {
    return QrCodeSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      format: QrFormat.fromCodeType(json['codeType'] as String) ??
          QrFormat.qrStandard,
      source: QrCodeSource.fromValue(json['source'] as String) ??
          QrCodeSource.created,
      createdAt: DateTime.parse(json['createdAt'] as String),
      category: json['category'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      filePath: json['filePath'] as String,
      contentType: QrContentType.values.firstWhere(
        (t) => t.name == json['contentType'],
        orElse: () => QrContentType.text,
      ),
    );
  }

  /// Convert to JSON map (for cache)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'codeType': format.codeType,
        'source': source.value,
        'createdAt': createdAt.toIso8601String(),
        if (category != null) 'category': category,
        if (tags.isNotEmpty) 'tags': tags,
        'filePath': filePath,
        'contentType': contentType.name,
      };

  @override
  String toString() => 'QrCodeSummary(id: $id, name: $name)';
}

/// Helper class for parsing WiFi QR content
class WifiQrContent {
  final String ssid;
  final String? password;
  final String authType; // WPA, WEP, nopass
  final bool hidden;

  WifiQrContent({
    required this.ssid,
    this.password,
    this.authType = 'WPA',
    this.hidden = false,
  });

  /// Parse from WiFi QR string
  factory WifiQrContent.parse(String content) {
    String ssid = '';
    String? password;
    String authType = 'WPA';
    bool hidden = false;

    // Remove WIFI: prefix
    String data = content;
    if (data.toUpperCase().startsWith('WIFI:')) {
      data = data.substring(5);
    }

    // Parse fields
    final parts = data.split(';');
    for (final part in parts) {
      if (part.isEmpty) continue;
      final colonIndex = part.indexOf(':');
      if (colonIndex == -1) continue;

      final key = part.substring(0, colonIndex).toUpperCase();
      final value = part.substring(colonIndex + 1);

      switch (key) {
        case 'S':
          ssid = value;
          break;
        case 'P':
          password = value;
          break;
        case 'T':
          authType = value;
          break;
        case 'H':
          hidden = value.toLowerCase() == 'true';
          break;
      }
    }

    return WifiQrContent(
      ssid: ssid,
      password: password,
      authType: authType,
      hidden: hidden,
    );
  }

  /// Generate WiFi QR string
  String toQrString() {
    final buffer = StringBuffer('WIFI:');
    buffer.write('T:$authType;');
    buffer.write('S:$ssid;');
    if (password != null && password!.isNotEmpty) {
      buffer.write('P:$password;');
    }
    if (hidden) {
      buffer.write('H:true;');
    }
    buffer.write(';');
    return buffer.toString();
  }

  @override
  String toString() => 'WifiQrContent(ssid: $ssid, authType: $authType)';
}
