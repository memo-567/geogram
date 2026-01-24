// Blossom (NOSTR file storage) HTTP handler for station server
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import '../../services/nostr_blossom_service.dart';

/// Handler for Blossom file storage endpoints
class BlossomHandler {
  final NostrBlossomService? Function() getBlossom;
  final void Function(String, String) log;

  BlossomHandler({
    required this.getBlossom,
    required this.log,
  });

  /// Check if Blossom service is available
  bool get isAvailable => getBlossom() != null;

  /// Handle Blossom requests
  /// Returns true if request was handled, false if not a Blossom path
  Future<bool> handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    if (!path.startsWith('/blossom')) return false;

    final blossom = getBlossom();
    if (blossom == null) {
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'error': 'Blossom service not available'}));
      return true;
    }

    if (method == 'POST' && path == '/blossom/upload') {
      await _handleUpload(request, blossom);
    } else if (method == 'GET' && path.startsWith('/blossom/')) {
      await _handleGet(request, blossom);
    } else if (method == 'HEAD' && path.startsWith('/blossom/')) {
      await _handleHead(request, blossom);
    } else if (method == 'DELETE' && path.startsWith('/blossom/')) {
      await _handleDelete(request, blossom);
    } else {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'Not found'}));
    }

    return true;
  }

  /// Handle POST /blossom/upload
  Future<void> _handleUpload(HttpRequest request, NostrBlossomService blossom) async {
    try {
      // Read request body
      final chunks = <List<int>>[];
      await for (final chunk in request) {
        chunks.add(chunk);
      }
      final bytes = Uint8List.fromList(chunks.expand((e) => e).toList());

      if (bytes.isEmpty) {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': 'Empty request body'}));
        return;
      }

      // Check size limits
      if (bytes.length > blossom.maxFileBytes) {
        request.response.statusCode = 413;
        request.response.write(jsonEncode({
          'error': 'File too large',
          'max_size': blossom.maxFileBytes,
          'actual_size': bytes.length,
        }));
        return;
      }

      // Detect MIME type
      final mimeType = lookupMimeType('', headerBytes: bytes) ?? 'application/octet-stream';

      // Store the file using ingestBytes
      final result = await blossom.ingestBytes(bytes: bytes, mime: mimeType);

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'hash': result.hash,
        'size': result.size,
        'type': result.mime ?? mimeType,
        'url': '/blossom/${result.hash}',
      }));

      log('INFO', 'Blossom upload: ${result.hash} (${result.size} bytes)');
    } catch (e) {
      log('ERROR', 'Blossom upload failed: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': e.toString()}));
    }
  }

  /// Handle GET /blossom/{hash}
  Future<void> _handleGet(HttpRequest request, NostrBlossomService blossom) async {
    final hash = _extractHash(request.uri.path);
    if (hash == null || hash.length != 64) {
      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': 'Invalid hash'}));
      return;
    }

    final file = blossom.getBlobFile(hash);
    if (file == null) {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'Blob not found'}));
      return;
    }

    final data = await file.readAsBytes();

    // Detect MIME type
    final mimeType = lookupMimeType('', headerBytes: data) ?? 'application/octet-stream';
    request.response.headers.contentType = ContentType.parse(mimeType);
    request.response.headers.add('Content-Length', data.length.toString());
    request.response.headers.add('Cache-Control', 'public, max-age=31536000, immutable');
    request.response.add(data);
  }

  /// Handle HEAD /blossom/{hash}
  Future<void> _handleHead(HttpRequest request, NostrBlossomService blossom) async {
    final hash = _extractHash(request.uri.path);
    if (hash == null || hash.length != 64) {
      request.response.statusCode = 400;
      return;
    }

    final file = blossom.getBlobFile(hash);
    if (file != null) {
      final data = await file.readAsBytes();
      final mimeType = lookupMimeType('', headerBytes: data) ?? 'application/octet-stream';
      request.response.headers.contentType = ContentType.parse(mimeType);
      request.response.headers.add('Content-Length', data.length.toString());
      request.response.statusCode = 200;
    } else {
      request.response.statusCode = 404;
    }
  }

  /// Handle DELETE /blossom/{hash}
  /// Requires authentication (handled by caller)
  Future<void> _handleDelete(HttpRequest request, NostrBlossomService blossom) async {
    // TODO: Implement authentication check
    // For now, return 403 Forbidden
    request.response.statusCode = 403;
    request.response.write(jsonEncode({'error': 'Authentication required'}));
  }

  /// Extract hash from path /blossom/{hash}
  String? _extractHash(String path) {
    if (!path.startsWith('/blossom/')) return null;
    final hash = path.substring('/blossom/'.length);
    // Remove any file extension
    final dotIndex = hash.indexOf('.');
    if (dotIndex > 0) {
      return hash.substring(0, dotIndex);
    }
    return hash;
  }

  /// Get storage statistics
  Map<String, dynamic> getStorageStats(NostrBlossomService blossom) {
    return {
      'max_bytes': blossom.maxBytes,
      'max_file_bytes': blossom.maxFileBytes,
    };
  }
}
