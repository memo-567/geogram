// Standalone test to verify tile fetching from relay vs internet
// Run with: dart test/tile_source_test.dart
//
// This test checks if tiles can be fetched from the relay and logs the source

import 'dart:io';
import 'package:http/http.dart' as http;

const String relayUrl = 'http://localhost:8080';
const String userCallsign = 'X1NZG9';

// Test tiles around Germany (lat: 49.683, lon: 8.622)
final testTiles = [
  [5, 16, 10],  // Germany area
  [5, 17, 10],
  [5, 16, 11],
  [6, 33, 21],
  [7, 66, 43],
];

Future<void> main() async {
  print('=== Tile Source Test ===\n');
  print('This test verifies that tiles can be fetched from the relay.');
  print('Relay URL: $relayUrl');
  print('User callsign: $userCallsign\n');

  // Step 1: Check relay status
  print('1. Checking relay status...');
  try {
    final statusResponse = await http.get(Uri.parse('$relayUrl/api/status'));
    if (statusResponse.statusCode == 200) {
      print('   PASS: Relay is running at $relayUrl');
    } else {
      print('   FAIL: Relay returned status ${statusResponse.statusCode}');
      exit(1);
    }
  } catch (e) {
    print('   FAIL: Relay not reachable: $e');
    print('   Please start the relay first: cd geogram-relay && java -jar target/geogram-relay.jar');
    exit(1);
  }

  // Test both standard and satellite tiles
  print('\n2. Testing STANDARD tiles (OSM)...');
  final standardResults = await _testTiles('standard');

  print('\n3. Testing SATELLITE tiles (Esri)...');
  final satelliteResults = await _testTiles('satellite');

  // Summary
  print('\n=== Final Summary ===');
  print('STANDARD tiles: ${standardResults['relay']} from relay, ${standardResults['internet']} from internet, ${standardResults['failed']} failed');
  print('SATELLITE tiles: ${satelliteResults['relay']} from relay, ${satelliteResults['internet']} from internet, ${satelliteResults['failed']} failed');

  final totalRelay = standardResults['relay']! + satelliteResults['relay']!;
  final totalInternet = standardResults['internet']! + satelliteResults['internet']!;
  final totalFailed = standardResults['failed']! + satelliteResults['failed']!;

  if (totalRelay == 0) {
    print('\nWARNING: No tiles came from relay!');
  } else {
    print('\nSUCCESS: $totalRelay total tiles fetched from relay');
  }

  print('\n=== Test Complete ===');
}

Future<Map<String, int>> _testTiles(String layer) async {
  int relaySuccess = 0;
  int internetSuccess = 0;
  int failed = 0;

  final layerParam = layer == 'satellite' ? '?layer=satellite' : '';
  print('   Relay URL template: $relayUrl/tiles/$userCallsign/{z}/{x}/{y}.png$layerParam');

  for (final tile in testTiles) {
    final z = tile[0];
    final x = tile[1];
    final y = tile[2];

    // Try relay first (mimicking desktop app behavior)
    final relayTileUrl = '$relayUrl/tiles/$userCallsign/$z/$x/$y.png$layerParam';
    print('\n   Tile [$z/$x/$y] ($layer):');
    print('   -> Trying RELAY: $relayTileUrl');

    try {
      final relayResponse = await http.get(Uri.parse(relayTileUrl))
          .timeout(const Duration(seconds: 10));

      if (relayResponse.statusCode == 200 && _isValidImage(relayResponse.bodyBytes)) {
        print('   -> SOURCE: RELAY (${relayResponse.bodyBytes.length} bytes)');
        relaySuccess++;
        continue;
      } else {
        print('   -> Relay returned ${relayResponse.statusCode}, trying internet...');
      }
    } catch (e) {
      print('   -> Relay failed: $e, trying internet...');
    }

    // Fall back to internet
    String internetUrl;
    if (layer == 'satellite') {
      // Esri uses z/y/x order
      internetUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x';
    } else {
      // OSM uses z/x/y order
      internetUrl = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    }
    print('   -> Trying INTERNET: $internetUrl');

    try {
      final response = await http.get(
        Uri.parse(internetUrl),
        headers: {'User-Agent': 'TileSourceTest/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && _isValidImage(response.bodyBytes)) {
        print('   -> SOURCE: INTERNET (${response.bodyBytes.length} bytes)');
        internetSuccess++;
      } else {
        print('   -> FAILED: Internet returned ${response.statusCode}');
        failed++;
      }
    } catch (e) {
      print('   -> FAILED: $e');
      failed++;
    }
  }

  return {'relay': relaySuccess, 'internet': internetSuccess, 'failed': failed};
}

bool _isValidImage(List<int> bytes) {
  if (bytes.length < 8) return false;
  // PNG signature: 89 50 4E 47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return true;
  }
  // JPEG signature: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  return false;
}
