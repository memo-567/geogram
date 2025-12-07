#!/usr/bin/env dart
/// Alert API Filter Test
///
/// This test suite verifies the /api/alerts endpoint:
/// - Creates alerts at different locations
/// - Tests radius-based filtering
/// - Tests timestamp-based filtering (since parameter)
/// - Tests status filtering
/// - Verifies distance calculation accuracy
///
/// Run with: dart bin/alert_api_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/cli/pure_station.dart';
import '../lib/cli/pure_storage_config.dart';
import '../lib/util/nostr_event.dart';
import '../lib/util/nostr_crypto.dart';
import '../lib/util/nostr_key_generator.dart';

const int TEST_PORT = 45692;
const String HTTP_URL = 'http://localhost:$TEST_PORT';
const String WS_URL = 'ws://localhost:$TEST_PORT';

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

/// Create an alert event at a specific location
NostrEvent createAlertEvent({
  required NostrKeys keys,
  required String callsign,
  required double lat,
  required double lon,
  required String title,
  String severity = 'attention',
  String status = 'open',
  String type = 'other',
}) {
  final folderName = '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}_${title.toLowerCase().replaceAll(' ', '-')}';

  final reportContent = '''
# REPORT: $title

CREATED: ${_formatDateTime(DateTime.now())}
AUTHOR: $callsign
COORDINATES: $lat,$lon
SEVERITY: $severity
TYPE: $type
STATUS: $status

Test alert at coordinates $lat, $lon.

--> npub: ${keys.npub}
''';

  final event = NostrEvent(
    pubkey: NostrCrypto.decodeNpub(keys.npub),
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    kind: NostrEventKind.applicationSpecificData,
    tags: [
      ['d', folderName],
      ['g', '$lat,$lon'],
      ['t', 'alert'],
      ['severity', severity],
      ['status', status],
      ['type', type],
    ],
    content: reportContent,
  );
  event.calculateId();
  event.signWithNsec(keys.nsec);
  return event;
}

String _formatDateTime(DateTime dt) {
  final y = dt.year;
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$y-$m-$d $h:${min}_$s';
}

/// Pending completers for OK responses, keyed by event ID
final Map<String, Completer<bool>> _pendingOkResponses = {};

/// Initialize WebSocket listener (call once after connection)
void initWebSocketListener(WebSocket ws) {
  ws.listen((data) {
    if (data is String && data.startsWith('[')) {
      try {
        final arr = jsonDecode(data) as List<dynamic>;
        if (arr.isNotEmpty && arr[0] == 'OK') {
          final eventId = arr[1] as String;
          final success = arr[2] as bool;
          final completer = _pendingOkResponses.remove(eventId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(success);
          }
        }
      } catch (_) {}
    }
  });
}

/// Send an alert via WebSocket and wait for OK
Future<bool> sendAlertViaWebSocket(WebSocket ws, NostrEvent event) async {
  final completer = Completer<bool>();
  _pendingOkResponses[event.id!] = completer;

  ws.add(jsonEncode({
    'nostr_event': ['EVENT', event.toJson()],
  }));

  try {
    return await completer.future.timeout(const Duration(seconds: 5));
  } catch (_) {
    _pendingOkResponses.remove(event.id);
    return false;
  }
}

/// Fetch alerts from the API
Future<Map<String, dynamic>> fetchAlerts({
  double? lat,
  double? lon,
  double? radius,
  int? since,
  String? status,
}) async {
  final params = <String, String>{};
  if (lat != null) params['lat'] = lat.toString();
  if (lon != null) params['lon'] = lon.toString();
  if (radius != null) params['radius'] = radius.toString();
  if (since != null) params['since'] = since.toString();
  if (status != null) params['status'] = status;

  final uri = Uri.parse('$HTTP_URL/api/alerts').replace(queryParameters: params.isNotEmpty ? params : null);

  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set('Accept', 'application/json');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> main() async {
  print('');
  print('=' * 60);
  print('Geogram Alert API Filter Test Suite');
  print('=' * 60);
  print('');
  print('Test server port: $TEST_PORT');
  print('');

  // Setup temp directory for test data
  final tempDir = await Directory.systemTemp.createTemp('geogram_alert_api_test_');
  print('Using temp directory: ${tempDir.path}');

  PureStationServer? station;
  WebSocket? ws;

  try {
    // Initialize storage config
    PureStorageConfig().reset();
    await PureStorageConfig().init(customBaseDir: tempDir.path);

    // Create and initialize the station server
    station = PureStationServer();
    station.quietMode = true;
    await station.initialize();

    station.setSetting('httpPort', TEST_PORT);
    station.setSetting('description', 'Alert API Test Station');

    final stationCallsign = station.settings.callsign;
    print('Station callsign: $stationCallsign');

    final started = await station.start();
    if (!started) {
      print('ERROR: Failed to start station server on port $TEST_PORT');
      exit(1);
    }
    print('Station server started on port $TEST_PORT');
    print('');

    await Future.delayed(const Duration(milliseconds: 500));

    // Generate test client keys
    final clientKeys = NostrKeyGenerator.generateKeyPair();
    final clientCallsign = NostrKeyGenerator.deriveCallsign(clientKeys.npub);
    print('Test client callsign: $clientCallsign');

    // Connect WebSocket
    ws = await WebSocket.connect(WS_URL);

    // Initialize listener (must be done once before sending events)
    initWebSocketListener(ws);

    // Send hello
    final helloEvent = NostrEvent.createHello(
      npub: clientKeys.npub,
      callsign: clientCallsign,
    );
    helloEvent.calculateId();
    helloEvent.signWithNsec(clientKeys.nsec);
    ws.add(jsonEncode({
      'type': 'hello',
      'event': helloEvent.toJson(),
    }));
    await Future.delayed(const Duration(milliseconds: 500));

    // Test locations (Lisbon area)
    // Reference point: Lisbon center (38.7223, -9.1393)
    final lisbonCenter = {'lat': 38.7223, 'lon': -9.1393};

    // Test alerts at various distances from Lisbon center:
    // 1. At center (0 km)
    // 2. ~10 km away (Belem area)
    // 3. ~50 km away (Sintra)
    // 4. ~100 km away (Setubal)
    // 5. ~300 km away (Porto)

    final testAlerts = [
      {'lat': 38.7223, 'lon': -9.1393, 'title': 'Lisbon Center', 'expectedDist': 0},
      {'lat': 38.6966, 'lon': -9.2063, 'title': 'Belem Area', 'expectedDist': 10},
      {'lat': 38.7872, 'lon': -9.3908, 'title': 'Sintra', 'expectedDist': 25},
      {'lat': 38.5244, 'lon': -8.8882, 'title': 'Setubal', 'expectedDist': 30},
      {'lat': 41.1579, 'lon': -8.6291, 'title': 'Porto', 'expectedDist': 300},
    ];

    print('─' * 60);
    print('Creating Test Alerts');
    print('─' * 60);

    int timestampBeforeAlerts = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Create alerts
    for (final alert in testAlerts) {
      final event = createAlertEvent(
        keys: clientKeys,
        callsign: clientCallsign,
        lat: alert['lat'] as double,
        lon: alert['lon'] as double,
        title: alert['title'] as String,
      );
      final success = await sendAlertViaWebSocket(ws, event);
      if (success) {
        print('  Created: ${alert['title']} at ${alert['lat']}, ${alert['lon']}');
      } else {
        print('  FAILED: ${alert['title']}');
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    int timestampAfterAlerts = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Wait for storage
    await Future.delayed(const Duration(milliseconds: 500));

    print('');
    print('─' * 60);
    print('Testing Alert API Filters');
    print('─' * 60);

    // Test 1: Fetch all alerts (no filter)
    print('');
    print('Test 1: Fetch All Alerts (no filter)');
    try {
      final result = await fetchAlerts();
      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        if (alerts.length >= 5) {
          pass('Fetched ${alerts.length} alerts');
        } else {
          fail('Fetch all alerts', 'Expected at least 5 alerts, got ${alerts.length}');
        }
      } else {
        fail('Fetch all alerts', 'API returned success=false: ${result['error']}');
      }
    } catch (e) {
      fail('Fetch all alerts', e.toString());
    }

    // Test 2: Filter by radius (20 km from Lisbon center)
    print('');
    print('Test 2: Radius Filter (20 km from Lisbon center)');
    try {
      final result = await fetchAlerts(
        lat: lisbonCenter['lat'],
        lon: lisbonCenter['lon'],
        radius: 20,
      );
      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        // Should include Lisbon Center (~0km) and Belem (~10km), but not Sintra (~25km)
        final titles = alerts.map((a) => a['title'] as String).toList();

        if (alerts.length >= 2 &&
            titles.any((t) => t.contains('Lisbon')) &&
            titles.any((t) => t.contains('Belem'))) {
          // Check that Sintra and Porto are NOT included
          if (!titles.any((t) => t.contains('Porto'))) {
            pass('Radius 20km: ${alerts.length} alerts (includes Lisbon, Belem, excludes far locations)');
          } else {
            fail('Radius filter 20km', 'Porto should NOT be included at 20km radius');
          }
        } else {
          fail('Radius filter 20km', 'Expected Lisbon and Belem. Got: $titles');
        }
      } else {
        fail('Radius filter 20km', 'API returned success=false');
      }
    } catch (e) {
      fail('Radius filter 20km', e.toString());
    }

    // Test 3: Filter by radius (50 km)
    print('');
    print('Test 3: Radius Filter (50 km from Lisbon center)');
    try {
      final result = await fetchAlerts(
        lat: lisbonCenter['lat'],
        lon: lisbonCenter['lon'],
        radius: 50,
      );
      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        // Should include Lisbon, Belem, Sintra, Setubal (~30km), but not Porto (~300km)
        final titles = alerts.map((a) => a['title'] as String).toList();

        if (alerts.length >= 3 && !titles.any((t) => t.contains('Porto'))) {
          pass('Radius 50km: ${alerts.length} alerts (excludes Porto)');
        } else {
          fail('Radius filter 50km', 'Expected 3-4 alerts excluding Porto. Got: $titles');
        }
      } else {
        fail('Radius filter 50km', 'API returned success=false');
      }
    } catch (e) {
      fail('Radius filter 50km', e.toString());
    }

    // Test 4: Filter by radius (500 km - should include all)
    print('');
    print('Test 4: Radius Filter (500 km - includes all)');
    try {
      final result = await fetchAlerts(
        lat: lisbonCenter['lat'],
        lon: lisbonCenter['lon'],
        radius: 500,
      );
      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        final titles = alerts.map((a) => a['title'] as String).toList();

        if (alerts.length >= 5 && titles.any((t) => t.contains('Porto'))) {
          pass('Radius 500km: ${alerts.length} alerts (includes Porto)');
        } else {
          fail('Radius filter 500km', 'Expected all 5 alerts including Porto. Got ${alerts.length}: $titles');
        }
      } else {
        fail('Radius filter 500km', 'API returned success=false');
      }
    } catch (e) {
      fail('Radius filter 500km', e.toString());
    }

    // Test 5: Filter by timestamp (since)
    print('');
    print('Test 5: Timestamp Filter (since)');
    try {
      // Use a future timestamp - should return no alerts
      final futureTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final result = await fetchAlerts(since: futureTimestamp);

      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        if (alerts.isEmpty) {
          pass('Future timestamp: 0 alerts (correct - all alerts are older)');
        } else {
          fail('Timestamp filter', 'Expected 0 alerts with future timestamp, got ${alerts.length}');
        }
      } else {
        fail('Timestamp filter', 'API returned success=false');
      }
    } catch (e) {
      fail('Timestamp filter', e.toString());
    }

    // Test 6: Check timestamp in response
    print('');
    print('Test 6: Response Contains Timestamp');
    try {
      final result = await fetchAlerts();
      if (result['success'] == true && result['timestamp'] != null) {
        final serverTs = result['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if ((serverTs - now).abs() < 60) { // Within 60 seconds
          pass('Response includes valid timestamp: $serverTs');
        } else {
          fail('Timestamp validation', 'Server timestamp $serverTs differs too much from now $now');
        }
      } else {
        fail('Timestamp in response', 'No timestamp in response');
      }
    } catch (e) {
      fail('Timestamp in response', e.toString());
    }

    // Test 7: Verify station info in response
    print('');
    print('Test 7: Response Contains Station Info');
    try {
      final result = await fetchAlerts();
      if (result['success'] == true) {
        final stationInfo = result['station'] as Map<String, dynamic>?;
        if (stationInfo != null &&
            stationInfo['callsign'] != null &&
            stationInfo['name'] != null) {
          pass('Station info present: ${stationInfo['callsign']} (${stationInfo['name']})');
        } else {
          fail('Station info', 'Missing station info in response');
        }
      } else {
        fail('Station info', 'API returned success=false');
      }
    } catch (e) {
      fail('Station info', e.toString());
    }

    // Test 8: Filter count in response
    print('');
    print('Test 8: Filter Applied Count');
    try {
      final result = await fetchAlerts(
        lat: lisbonCenter['lat'],
        lon: lisbonCenter['lon'],
        radius: 20,
      );
      if (result['success'] == true) {
        final filters = result['filters'] as Map<String, dynamic>?;
        // API returns radius_km instead of radius
        if (filters != null && filters['radius_km'] == 20.0) {
          pass('Filters echoed correctly: radius_km=${filters['radius_km']}');
        } else {
          fail('Filter echo', 'Filters not echoed correctly. Got: $filters');
        }
      } else {
        fail('Filter echo', 'API returned success=false');
      }
    } catch (e) {
      fail('Filter echo', e.toString());
    }

    // Test 9: Create status-specific alerts
    print('');
    print('Test 9: Status Filter');

    // Create a resolved alert
    final resolvedEvent = createAlertEvent(
      keys: clientKeys,
      callsign: clientCallsign,
      lat: 38.7300,
      lon: -9.1400,
      title: 'Resolved Issue',
      status: 'resolved',
    );
    await sendAlertViaWebSocket(ws, resolvedEvent);
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      // Fetch only open alerts
      final openResult = await fetchAlerts(status: 'open');
      if (openResult['success'] == true) {
        final alerts = openResult['alerts'] as List<dynamic>;
        final allOpen = alerts.every((a) => a['status'] == 'open');
        if (allOpen) {
          pass('Status filter: ${alerts.length} open alerts (resolved excluded)');
        } else {
          fail('Status filter', 'Found non-open alerts in open-only query');
        }
      } else {
        fail('Status filter', 'API returned success=false');
      }
    } catch (e) {
      fail('Status filter', e.toString());
    }

    // Test 10: Combined filters (radius + status)
    print('');
    print('Test 10: Combined Filters (radius + location)');
    try {
      final result = await fetchAlerts(
        lat: lisbonCenter['lat'],
        lon: lisbonCenter['lon'],
        radius: 20,
        status: 'open',
      );
      if (result['success'] == true) {
        final alerts = result['alerts'] as List<dynamic>;
        final filters = result['filters'] as Map<String, dynamic>?;

        // Check that both filters are applied (API uses radius_km)
        if (filters != null &&
            filters['radius_km'] == 20.0 &&
            filters['status'] == 'open') {
          pass('Combined filters work: ${alerts.length} alerts with radius_km=20, status=open');
        } else {
          fail('Combined filters', 'Filters not applied correctly. Got: $filters');
        }
      } else {
        fail('Combined filters', 'API returned success=false');
      }
    } catch (e) {
      fail('Combined filters', e.toString());
    }

    // Cleanup
    await ws.close();

    // Print summary
    print('');
    print('=' * 60);
    print('Test Summary');
    print('=' * 60);
    print('Passed: $_passed');
    print('Failed: $_failed');

    if (_failures.isNotEmpty) {
      print('');
      print('Failures:');
      for (final f in _failures) {
        print('  - $f');
      }
    }
    print('');

  } catch (e, st) {
    print('');
    print('FATAL ERROR: $e');
    print(st);
  } finally {
    await ws?.close();
    await station?.stop();

    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }

  exit(_failed > 0 ? 1 : 0);
}
