// Tile server HTTP handler for station server
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../station_settings.dart';
import '../station_tile_cache.dart';
import '../station_stats.dart';
import '../../version.dart';

/// Handler for tile server endpoints
class TileHandler {
  final StationSettings Function() getSettings;
  final StationTileCache tileCache;
  final StationStats stats;
  final String tilesDirectory;
  final void Function(String, String) log;

  TileHandler({
    required this.getSettings,
    required this.tileCache,
    required this.stats,
    required this.tilesDirectory,
    required this.log,
  });

  /// Handle GET /tiles/{z}/{x}/{y}.png
  Future<void> handleTileRequest(HttpRequest request) async {
    final settings = getSettings();

    if (!settings.tileServerEnabled) {
      request.response.statusCode = 503;
      request.response.write('Tile server disabled');
      return;
    }

    final path = request.uri.path;
    final parts = path.split('/');
    // /tiles/{z}/{x}/{y}.png
    if (parts.length < 5) {
      request.response.statusCode = 400;
      request.response.write('Invalid tile path');
      return;
    }

    final z = int.tryParse(parts[2]);
    final x = int.tryParse(parts[3]);
    final yPart = parts[4].replaceAll('.png', '');
    final y = int.tryParse(yPart);

    if (z == null || x == null || y == null) {
      request.response.statusCode = 400;
      request.response.write('Invalid tile coordinates');
      return;
    }

    if (z > settings.maxZoomLevel) {
      request.response.statusCode = 400;
      request.response.write('Zoom level exceeds maximum (${settings.maxZoomLevel})');
      return;
    }

    final cacheKey = '$z/$x/$y';

    // Check memory cache first
    final cached = tileCache.get(cacheKey);
    if (cached != null) {
      stats.recordTileRequest(fromCache: true);
      request.response.headers.contentType = ContentType.parse('image/png');
      request.response.add(cached);
      return;
    }

    // Try to load from disk
    final tilePath = '$tilesDirectory/$z/$x/$y.png';
    final tileFile = File(tilePath);
    if (await tileFile.exists()) {
      try {
        final data = await tileFile.readAsBytes();
        if (StationTileCache.isValidImageData(data)) {
          tileCache.put(cacheKey, data);
          stats.recordTileRequest(fromCache: true);
          request.response.headers.contentType = ContentType.parse('image/png');
          request.response.add(data);
          return;
        }
      } catch (e) {
        log('WARN', 'Failed to read tile from disk: $e');
      }
    }

    // Fetch from OSM if fallback is enabled
    if (settings.osmFallbackEnabled) {
      final data = await _fetchFromOsm(z, x, y, settings.httpRequestTimeout);
      if (data != null) {
        tileCache.put(cacheKey, data);
        stats.recordTileCached();

        // Save to disk asynchronously
        _saveTileToDisk(tilePath, data);

        request.response.headers.contentType = ContentType.parse('image/png');
        request.response.add(data);
        return;
      }
    }

    request.response.statusCode = 404;
    request.response.write('Tile not found');
  }

  /// Fetch tile from OpenStreetMap
  Future<Uint8List?> _fetchFromOsm(int z, int x, int y, int timeout) async {
    try {
      final osmUrl = 'https://tile.openstreetmap.org/$z/$x/$y.png';
      final response = await http.get(
        Uri.parse(osmUrl),
        headers: {'User-Agent': 'Geogram/$appVersion'},
      ).timeout(Duration(milliseconds: timeout));

      if (response.statusCode == 200 && StationTileCache.isValidImageData(response.bodyBytes)) {
        return Uint8List.fromList(response.bodyBytes);
      }
    } catch (e) {
      log('WARN', 'Failed to fetch tile from OSM: $e');
    }
    return null;
  }

  /// Save tile to disk asynchronously
  void _saveTileToDisk(String tilePath, Uint8List data) {
    Future(() async {
      try {
        final file = File(tilePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data);
      } catch (e) {
        log('WARN', 'Failed to save tile to disk: $e');
      }
    });
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_tiles': tileCache.size,
      'cache_size_bytes': tileCache.sizeBytes,
      'tiles_cached': stats.tilesCached,
      'tiles_served_from_cache': stats.tilesServedFromCache,
      'tiles_downloaded': stats.tilesDownloaded,
    };
  }

  /// Clear tile cache
  void clearCache() {
    tileCache.clear();
    log('INFO', 'Tile cache cleared');
  }
}
