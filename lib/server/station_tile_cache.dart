// Unified tile cache for station server
import 'dart:typed_data';

/// Tile cache for station server
/// LRU cache with size limits for map tile data
class StationTileCache {
  final Map<String, Uint8List> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  int _currentSize = 0;
  final int maxSizeBytes;

  StationTileCache({int maxSizeMB = 500}) : maxSizeBytes = maxSizeMB * 1024 * 1024;

  /// Get tile from cache, updating access time
  Uint8List? get(String key) {
    final data = _cache[key];
    if (data != null) {
      _timestamps[key] = DateTime.now();
    }
    return data;
  }

  /// Put tile into cache, evicting old entries if needed
  void put(String key, Uint8List data) {
    // Remove if already exists
    if (_cache.containsKey(key)) {
      _currentSize -= _cache[key]!.length;
    }

    // Evict old entries if needed
    while (_currentSize + data.length > maxSizeBytes && _cache.isNotEmpty) {
      _evictOldest();
    }

    _cache[key] = data;
    _timestamps[key] = DateTime.now();
    _currentSize += data.length;
  }

  void _evictOldest() {
    if (_timestamps.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _timestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestTime = entry.value;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null && _cache.containsKey(oldestKey)) {
      _currentSize -= _cache[oldestKey]!.length;
      _cache.remove(oldestKey);
      _timestamps.remove(oldestKey);
    }
  }

  /// Number of cached tiles
  int get size => _cache.length;

  /// Total size of cached data in bytes
  int get sizeBytes => _currentSize;

  /// Clear all cached tiles
  void clear() {
    _cache.clear();
    _timestamps.clear();
    _currentSize = 0;
  }

  /// Validate tile image data by checking header and basic structure
  /// This prevents caching corrupt tiles from bad network connections
  static bool isValidImageData(Uint8List data) {
    if (data.length < 8) return false;

    // Check for PNG signature
    final isPng = data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47;
    // Check for JPEG signature (used by satellite tiles)
    final isJpeg = data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF;

    if (!isPng && !isJpeg) return false;

    // For PNG, verify IEND chunk exists (basic integrity check)
    if (isPng) {
      // Look for IEND marker in last 12 bytes
      if (data.length < 12) return false;
      final end = data.sublist(data.length - 12);
      // IEND chunk: length(4) + 'IEND'(4) + CRC(4)
      final hasIend = end[4] == 0x49 && end[5] == 0x45 &&
                      end[6] == 0x4E && end[7] == 0x44;
      return hasIend;
    }

    // For JPEG, verify EOI marker exists
    if (isJpeg) {
      // JPEG should end with FFD9
      return data[data.length - 2] == 0xFF && data[data.length - 1] == 0xD9;
    }

    return true;
  }
}
