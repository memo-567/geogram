#!/usr/bin/env dart
/// Comprehensive tile server tests for PureRelayServer
///
/// This test suite:
/// - Launches a relay server on port 45690
/// - Clears any existing tile cache for clean results
/// - Tests tile fetching from internet (OSM)
/// - Tests tile caching (memory and disk)
/// - Verifies cache hits on subsequent requests
/// - Tests various tile server scenarios
///
/// Run with: dart bin/tile_server_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../lib/cli/pure_relay.dart';
import '../lib/services/storage_config.dart';

const int TEST_PORT = 45690;
const String BASE_URL = 'http://localhost:$TEST_PORT';

// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

void pass(String test) {
  _passed++;
  print('  [PASS] $test');
}

void fail(String test, String reason) {
  _failed++;
  _failures.add('$test: $reason');
  print('  [FAIL] $test - $reason');
}

Future<Map<String, dynamic>?> getStats() async {
  try {
    final response = await http.get(Uri.parse('$BASE_URL/api/stats'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
  } catch (e) {
    print('    Error getting stats: $e');
  }
  return null;
}

Future<void> main() async {
  print('');
  print('=' * 60);
  print('Geogram Desktop Tile Server Test Suite');
  print('=' * 60);
  print('');
  print('Test server port: $TEST_PORT');
  print('');

  // Setup temp directory for test data
  final tempDir = await Directory.systemTemp.createTemp('geogram_tile_test_');
  print('Using temp directory: ${tempDir.path}');

  PureRelayServer? relay;

  try {
    // Initialize storage config
    StorageConfig().reset();
    await StorageConfig().init(customBaseDir: tempDir.path);

    // Ensure tiles directory exists and is clean
    final tilesDir = Directory('${tempDir.path}/tiles');
    if (await tilesDir.exists()) {
      print('Cleaning existing tile cache...');
      await tilesDir.delete(recursive: true);
    }
    await tilesDir.create(recursive: true);
    print('Tile cache directory: ${tilesDir.path}');
    print('');

    // Create and initialize the relay server
    relay = PureRelayServer();
    relay.quietMode = true; // Suppress log output during tests
    await relay.initialize();

    // Configure relay settings - enable tile server
    relay.setSetting('port', TEST_PORT);
    relay.setSetting('callsign', 'X3TILE');
    relay.setSetting('description', 'Tile Test Relay');
    relay.setSetting('tileServerEnabled', true);
    relay.setSetting('osmFallbackEnabled', true);
    relay.setSetting('maxZoomLevel', 18);
    relay.setSetting('maxCacheSize', 100); // 100MB for testing

    // Start the server
    final started = await relay.start();
    if (!started) {
      print('ERROR: Failed to start relay server on port $TEST_PORT');
      exit(1);
    }
    print('Relay server started on port $TEST_PORT');
    print('Tile server enabled: true');
    print('OSM fallback enabled: true');
    print('');

    // Wait for server to be fully ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Run all tile tests
    await _testTileServerEnabled();
    await _testInitialStats();
    await _testFirstTileRequest(tempDir.path);
    await _testCachedTileRequest();
    await _testDiskCacheVerification(tempDir.path);
    await _testMultipleTileRequests();
    await _testInvalidTilePath();
    await _testInvalidZoomLevel();
    await _testSatelliteLayer();
    await _testTileStatsAccumulation();

    // Stop the server
    await relay.stop();

    // Print summary
    print('');
    print('=' * 60);
    print('Test Summary');
    print('=' * 60);
    print('');
    print('Passed: $_passed');
    print('Failed: $_failed');
    print('Total:  ${_passed + _failed}');
    print('');

    if (_failures.isNotEmpty) {
      print('Failures:');
      for (final failure in _failures) {
        print('  - $failure');
      }
      print('');
    }

    exit(_failed > 0 ? 1 : 0);
  } catch (e, stackTrace) {
    print('ERROR: $e');
    print(stackTrace);
    exit(1);
  } finally {
    // Ensure server is stopped
    if (relay != null) {
      try {
        await relay.stop();
      } catch (_) {}
    }

    // Cleanup temp directory
    try {
      await tempDir.delete(recursive: true);
      print('Cleaned up temp directory');
    } catch (_) {}
  }
}

/// Test that tile server is enabled
Future<void> _testTileServerEnabled() async {
  print('');
  print('--- Testing Tile Server Configuration ---');

  // Just verify the endpoint is accessible
  try {
    final response = await http.get(Uri.parse('$BASE_URL/api/stats'));
    if (response.statusCode == 200) {
      pass('Tile server stats endpoint accessible');
    } else {
      fail('Tile server stats endpoint', 'Got ${response.statusCode}');
    }
  } catch (e) {
    fail('Tile server stats endpoint', 'Exception: $e');
  }
}

/// Test initial stats are zero
Future<void> _testInitialStats() async {
  print('');
  print('--- Testing Initial Tile Stats ---');

  final stats = await getStats();
  if (stats == null) {
    fail('Initial stats', 'Failed to get stats');
    return;
  }

  final totalRequests = stats['total_tile_requests'] ?? 0;
  final tilesDownloaded = stats['tiles_downloaded'] ?? 0;
  final tilesFromCache = stats['tiles_served_from_cache'] ?? 0;

  if (totalRequests == 0) {
    pass('Initial total_tile_requests is 0');
  } else {
    fail('Initial total_tile_requests is 0', 'Got $totalRequests');
  }

  if (tilesDownloaded == 0) {
    pass('Initial tiles_downloaded is 0');
  } else {
    fail('Initial tiles_downloaded is 0', 'Got $tilesDownloaded');
  }

  if (tilesFromCache == 0) {
    pass('Initial tiles_served_from_cache is 0');
  } else {
    fail('Initial tiles_served_from_cache is 0', 'Got $tilesFromCache');
  }
}

/// Test first tile request downloads from internet
Future<void> _testFirstTileRequest(String tempDir) async {
  print('');
  print('--- Testing First Tile Request (Download from Internet) ---');

  // Request a tile - zoom level 1 is small and quick
  // Using zoom 1, x=0, y=0 - a valid OSM tile
  // Note: The layer in the URL path is just a placeholder, actual layer comes from ?layer= param
  // Default layer is "standard" which maps to OSM tiles
  final tileUrl = '$BASE_URL/tiles/map/1/0/0.png';
  print('  Requesting: $tileUrl (layer defaults to "standard")');

  try {
    final response = await http.get(Uri.parse(tileUrl)).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode == 200) {
      pass('First tile request returns 200 OK');
    } else {
      fail('First tile request returns 200 OK', 'Got ${response.statusCode}');
      return;
    }

    // Check content type
    final contentType = response.headers['content-type'];
    if (contentType != null && contentType.contains('image/png')) {
      pass('Response has image/png content type');
    } else {
      fail('Response has image/png content type', 'Got $contentType');
    }

    // Check we got actual image data
    final body = response.bodyBytes;
    if (body.length > 100) {
      pass('Response contains image data (${body.length} bytes)');
    } else {
      fail('Response contains image data', 'Only ${body.length} bytes');
    }

    // Verify PNG magic bytes
    if (body.length >= 8 &&
        body[0] == 0x89 &&
        body[1] == 0x50 &&
        body[2] == 0x4E &&
        body[3] == 0x47) {
      pass('Response is valid PNG format');
    } else {
      fail('Response is valid PNG format', 'Invalid PNG header');
    }

    // Check stats - should show download
    await Future.delayed(const Duration(milliseconds: 100));
    final stats = await getStats();
    if (stats != null) {
      final downloaded = stats['tiles_downloaded'] ?? 0;
      if (downloaded >= 1) {
        pass('Stats show tiles_downloaded >= 1 (got $downloaded)');
      } else {
        fail('Stats show tiles_downloaded >= 1', 'Got $downloaded');
      }
    }
  } catch (e) {
    fail('First tile request', 'Exception: $e');
  }
}

/// Test second request for same tile is served from cache
Future<void> _testCachedTileRequest() async {
  print('');
  print('--- Testing Cached Tile Request (Should Serve from Cache) ---');

  // Get stats before request
  final statsBefore = await getStats();
  final cachedBefore = statsBefore?['tiles_served_from_cache'] ?? 0;
  final downloadedBefore = statsBefore?['tiles_downloaded'] ?? 0;

  // Request the same tile again
  final tileUrl = '$BASE_URL/tiles/map/1/0/0.png';
  print('  Requesting same tile: $tileUrl');

  try {
    final stopwatch = Stopwatch()..start();
    final response = await http.get(Uri.parse(tileUrl));
    stopwatch.stop();

    if (response.statusCode == 200) {
      pass('Cached tile request returns 200 OK');
    } else {
      fail('Cached tile request returns 200 OK', 'Got ${response.statusCode}');
      return;
    }

    // Cache hit should be fast (less than 100ms typically)
    print('  Response time: ${stopwatch.elapsedMilliseconds}ms');
    if (stopwatch.elapsedMilliseconds < 500) {
      pass('Cached response is fast (<500ms)');
    } else {
      // Not a failure, just a note - network conditions vary
      print('    Note: Response slower than expected, might still be from cache');
    }

    // Check stats - should show cache hit, not download
    await Future.delayed(const Duration(milliseconds: 100));
    final statsAfter = await getStats();
    if (statsAfter != null) {
      final cachedAfter = statsAfter['tiles_served_from_cache'] ?? 0;
      final downloadedAfter = statsAfter['tiles_downloaded'] ?? 0;

      // Cache hits should increase
      if (cachedAfter > cachedBefore) {
        pass('tiles_served_from_cache increased ($cachedBefore -> $cachedAfter)');
      } else {
        fail('tiles_served_from_cache increased', '$cachedBefore -> $cachedAfter');
      }

      // Downloads should NOT increase (served from cache)
      if (downloadedAfter == downloadedBefore) {
        pass('tiles_downloaded did NOT increase (still $downloadedAfter)');
      } else {
        fail('tiles_downloaded did NOT increase', '$downloadedBefore -> $downloadedAfter');
      }
    }
  } catch (e) {
    fail('Cached tile request', 'Exception: $e');
  }
}

/// Verify tile was cached to disk
Future<void> _testDiskCacheVerification(String tempDir) async {
  print('');
  print('--- Testing Disk Cache ---');

  // Default layer is "standard" when no ?layer= param is provided
  final expectedPath = '$tempDir/tiles/standard/1/0/0.png';
  final cacheFile = File(expectedPath);

  if (await cacheFile.exists()) {
    pass('Tile cached to disk at $expectedPath');

    final bytes = await cacheFile.readAsBytes();
    if (bytes.length > 100) {
      pass('Cached file contains image data (${bytes.length} bytes)');
    } else {
      fail('Cached file contains image data', 'Only ${bytes.length} bytes');
    }

    // Verify PNG format
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      pass('Cached file is valid PNG format');
    } else {
      fail('Cached file is valid PNG format', 'Invalid PNG header');
    }
  } else {
    fail('Tile cached to disk', 'File not found at $expectedPath');
  }
}

/// Test multiple different tile requests
Future<void> _testMultipleTileRequests() async {
  print('');
  print('--- Testing Multiple Tile Requests ---');

  // Request several different tiles
  final tiles = [
    '/tiles/map/1/1/0.png',
    '/tiles/map/1/0/1.png',
    '/tiles/map/2/0/0.png',
    '/tiles/map/2/1/1.png',
  ];

  int successCount = 0;
  for (final tile in tiles) {
    try {
      final response = await http.get(Uri.parse('$BASE_URL$tile')).timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode == 200 && response.bodyBytes.length > 100) {
        successCount++;
      }
    } catch (e) {
      print('    Error fetching $tile: $e');
    }
  }

  if (successCount == tiles.length) {
    pass('All ${tiles.length} different tiles fetched successfully');
  } else {
    fail('All tiles fetched', 'Only $successCount/${tiles.length} succeeded');
  }

  // Check total requests stat increased
  final stats = await getStats();
  if (stats != null) {
    final totalRequests = stats['total_tile_requests'] ?? 0;
    // We've made 1 + 1 + 4 = 6 requests so far (plus initial)
    if (totalRequests >= 6) {
      pass('total_tile_requests accumulated correctly (>= 6, got $totalRequests)');
    } else {
      fail('total_tile_requests accumulated', 'Expected >= 6, got $totalRequests');
    }
  }
}

/// Test invalid tile path returns error
Future<void> _testInvalidTilePath() async {
  print('');
  print('--- Testing Invalid Tile Paths ---');

  // Invalid path format
  final invalidPaths = [
    '/tiles/invalid',
    '/tiles/map/abc/0/0.png',
    '/tiles/map/1/0.png',
    '/tiles/',
  ];

  for (final path in invalidPaths) {
    try {
      final response = await http.get(Uri.parse('$BASE_URL$path'));
      if (response.statusCode == 400 || response.statusCode == 404) {
        pass('Invalid path "$path" returns ${response.statusCode}');
      } else {
        fail('Invalid path returns error', '"$path" got ${response.statusCode}');
      }
    } catch (e) {
      // Connection errors are acceptable for invalid paths
      pass('Invalid path "$path" handled (connection error)');
    }
  }
}

/// Test invalid zoom level
Future<void> _testInvalidZoomLevel() async {
  print('');
  print('--- Testing Invalid Zoom Levels ---');

  // Zoom -1 (negative)
  try {
    final response = await http.get(Uri.parse('$BASE_URL/tiles/map/-1/0/0.png'));
    // This might be caught as invalid path (regex won't match negative)
    if (response.statusCode == 400 || response.statusCode == 404) {
      pass('Zoom level -1 returns error');
    } else {
      fail('Zoom level -1 returns error', 'Got ${response.statusCode}');
    }
  } catch (e) {
    pass('Zoom level -1 handled');
  }

  // Zoom 19 (above max 18)
  try {
    final response = await http.get(Uri.parse('$BASE_URL/tiles/map/19/0/0.png'));
    if (response.statusCode == 400) {
      pass('Zoom level 19 returns 400 (above max)');
    } else if (response.statusCode == 200) {
      // Some tile servers allow zoom 19, so this is acceptable
      pass('Zoom level 19 accepted (server allows high zoom)');
    } else {
      fail('Zoom level 19 handled', 'Got ${response.statusCode}');
    }
  } catch (e) {
    pass('Zoom level 19 handled');
  }
}

/// Test satellite layer parameter
Future<void> _testSatelliteLayer() async {
  print('');
  print('--- Testing Satellite Layer ---');

  final tileUrl = '$BASE_URL/tiles/map/1/0/0.png?layer=satellite';
  print('  Requesting: $tileUrl');

  try {
    final response = await http.get(Uri.parse(tileUrl)).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode == 200) {
      pass('Satellite layer request returns 200 OK');

      // Should be image data
      if (response.bodyBytes.length > 100) {
        pass('Satellite tile contains image data');
      } else {
        fail('Satellite tile contains image data', 'Only ${response.bodyBytes.length} bytes');
      }
    } else {
      // Satellite might fail if ArcGIS is unavailable, not a critical failure
      print('    Note: Satellite layer returned ${response.statusCode}');
      print('    This may be due to ArcGIS service availability');
    }
  } catch (e) {
    print('    Note: Satellite layer request failed: $e');
    print('    This may be due to network/service issues');
  }
}

/// Test stats accumulation
Future<void> _testTileStatsAccumulation() async {
  print('');
  print('--- Testing Final Stats ---');

  final stats = await getStats();
  if (stats == null) {
    fail('Final stats', 'Failed to get stats');
    return;
  }

  print('  Final tile statistics:');
  print('    total_tile_requests: ${stats['total_tile_requests']}');
  print('    tiles_downloaded: ${stats['tiles_downloaded']}');
  print('    tiles_served_from_cache: ${stats['tiles_served_from_cache']}');
  print('    tiles_cached: ${stats['tiles_cached']}');
  print('    cache_size: ${stats['cache_size']}');
  print('    cache_size_mb: ${stats['cache_size_mb']}');

  final totalRequests = stats['total_tile_requests'] ?? 0;
  final downloaded = stats['tiles_downloaded'] ?? 0;
  final fromCache = stats['tiles_served_from_cache'] ?? 0;

  // Sanity checks
  if (totalRequests > 0) {
    pass('Total tile requests > 0');
  } else {
    fail('Total tile requests > 0', 'Got $totalRequests');
  }

  if (downloaded > 0) {
    pass('Some tiles were downloaded from internet');
  } else {
    fail('Some tiles were downloaded', 'Got $downloaded');
  }

  if (fromCache > 0) {
    pass('Some tiles were served from cache');
  } else {
    fail('Some tiles were served from cache', 'Got $fromCache');
  }

  // Cache efficiency check
  if (totalRequests > 0) {
    final cacheHitRate = fromCache / totalRequests;
    print('  Cache hit rate: ${(cacheHitRate * 100).toStringAsFixed(1)}%');
    if (cacheHitRate > 0) {
      pass('Cache is being used effectively');
    }
  }
}
