/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;
import 'profile_service.dart';
import 'relay_service.dart';
import 'log_service.dart';

/// Centralized service for managing map tiles with offline caching
/// This ensures all map features use the same caching mechanism
class MapTileService {
  static final MapTileService _instance = MapTileService._internal();
  factory MapTileService() => _instance;
  MapTileService._internal();

  final ProfileService _profileService = ProfileService();
  bool _initialized = false;
  fmtc.FMTCStore? _tileStore;

  /// Initialize the tile caching system
  /// Should be called once at app startup or before first map use
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    try {
      await fmtc.FMTCObjectBoxBackend().initialise();
      _tileStore = fmtc.FMTCStore('mapTiles');
      await _tileStore!.manage.create();
      _initialized = true;
      LogService().log('MapTileService: Tile cache initialized successfully');
    } catch (e) {
      LogService().log('MapTileService: Failed to initialize tile cache: $e');
      _initialized = false;
    }
  }

  /// Get the tile URL - uses relay if available, otherwise fallback to OSM
  String getTileUrl() {
    try {
      final relay = RelayService().getPreferredRelay();
      final profile = _profileService.getProfile();

      // Check if we have both a relay and a callsign
      if (relay != null && relay.url.isNotEmpty && profile.callsign.isNotEmpty) {
        // Use relay tile server - convert WebSocket URL to HTTP URL
        var relayUrl = relay.url;

        // Convert ws:// to http:// and wss:// to https://
        if (relayUrl.startsWith('ws://')) {
          relayUrl = relayUrl.replaceFirst('ws://', 'http://');
        } else if (relayUrl.startsWith('wss://')) {
          relayUrl = relayUrl.replaceFirst('wss://', 'https://');
        }

        // Remove trailing slash if present
        if (relayUrl.endsWith('/')) {
          relayUrl = relayUrl.substring(0, relayUrl.length - 1);
        }

        return '$relayUrl/tiles/${profile.callsign}/{z}/{x}/{y}.png';
      }
    } catch (e) {
      LogService().log('MapTileService: Error getting relay tile URL: $e');
    }

    // Fallback to OpenStreetMap
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Get the tile provider with caching if available
  TileProvider getTileProvider() {
    if (_initialized && _tileStore != null && !kIsWeb) {
      return _tileStore!.getTileProvider();
    }
    // Fallback to network-only provider
    return NetworkTileProvider();
  }

  /// Check if tile caching is available and initialized
  bool get isCacheInitialized => _initialized && !kIsWeb;

  /// Get the tile store (for advanced operations if needed)
  fmtc.FMTCStore? get tileStore => _tileStore;

  /// Clear all cached tiles (useful for troubleshooting or storage management)
  Future<void> clearCache() async {
    if (_tileStore != null && !kIsWeb) {
      try {
        await _tileStore!.manage.delete();
        await _tileStore!.manage.create();
        LogService().log('MapTileService: Cache cleared successfully');
      } catch (e) {
        LogService().log('MapTileService: Error clearing cache: $e');
      }
    }
  }
}
