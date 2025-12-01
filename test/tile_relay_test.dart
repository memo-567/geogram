// Test script to verify tile fetching from relay
// Run with: dart test/tile_relay_test.dart

import 'dart:io';
import 'package:http/http.dart' as http;

const String relayUrl = 'http://localhost:8080';
const String userCallsign = 'X1NZG9';

Future<void> main() async {
  print('=== Tile Relay Test ===\n');

  // Step 1: Check if relay is running
  print('1. Checking relay status...');
  try {
    final statusResponse = await http.get(Uri.parse('$relayUrl/api/status'));
    if (statusResponse.statusCode == 200) {
      print('   ✓ Relay is running at $relayUrl');
    } else {
      print('   ✗ Relay returned status ${statusResponse.statusCode}');
      exit(1);
    }
  } catch (e) {
    print('   ✗ Relay not reachable: $e');
    print('   Please start the relay first: ./start.sh 8080');
    exit(1);
  }

  // Step 2: Test direct tile request to relay
  print('\n2. Testing direct tile request to relay...');
  final testTiles = [
    [5, 16, 10],
    [6, 32, 21],
    [7, 65, 42],
    [8, 131, 85],
  ];

  for (final tile in testTiles) {
    final z = tile[0];
    final x = tile[1];
    final y = tile[2];
    final tileUrl = '$relayUrl/tiles/$userCallsign/$z/$x/$y.png';

    print('   Requesting: $tileUrl');
    try {
      final response = await http.get(Uri.parse(tileUrl));
      if (response.statusCode == 200) {
        final isValidPng = response.bodyBytes.length > 8 &&
            response.bodyBytes[0] == 0x89 &&
            response.bodyBytes[1] == 0x50 &&
            response.bodyBytes[2] == 0x4E &&
            response.bodyBytes[3] == 0x47;
        if (isValidPng) {
          print('   ✓ Got valid PNG (${response.bodyBytes.length} bytes)');
        } else {
          print('   ✗ Response is not a valid PNG');
        }
      } else {
        print('   ✗ Status ${response.statusCode}');
      }
    } catch (e) {
      print('   ✗ Error: $e');
    }
  }

  // Step 3: Check relay tile cache
  print('\n3. Checking relay tile cache directory...');
  final cacheDir = Directory('/home/brito/code/geograms/geogram-relay/tiles/$userCallsign');
  if (await cacheDir.exists()) {
    final files = await cacheDir.list(recursive: true).where((e) => e.path.endsWith('.png')).length;
    print('   ✓ Cache directory exists with tiles');
  } else {
    print('   ✗ Cache directory NOT created: ${cacheDir.path}');
    print('   This means the relay is NOT caching tiles!');
  }

  // Step 4: Simulate what geogram-desktop MapTileService does
  print('\n4. Simulating MapTileService relay URL generation...');
  final wsUrl = 'ws://localhost:8080';
  var httpUrl = wsUrl.replaceFirst('ws://', 'http://');
  if (httpUrl.endsWith('/')) {
    httpUrl = httpUrl.substring(0, httpUrl.length - 1);
  }
  final relayTileUrl = '$httpUrl/tiles/$userCallsign/{z}/{x}/{y}.png';
  print('   Generated URL template: $relayTileUrl');

  // Test with actual coordinates
  final testUrl = relayTileUrl
      .replaceAll('{z}', '5')
      .replaceAll('{x}', '17')
      .replaceAll('{y}', '11');
  print('   Test URL: $testUrl');

  try {
    final response = await http.get(Uri.parse(testUrl));
    print('   Response: ${response.statusCode} (${response.bodyBytes.length} bytes)');
  } catch (e) {
    print('   Error: $e');
  }

  print('\n=== Test Complete ===');
}
