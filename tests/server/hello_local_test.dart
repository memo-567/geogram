#!/usr/bin/env dart
/// Local HELLO Handshake Test
///
/// Tests the HELLO handshake fix locally before deploying to p2p.radio.
/// Specifically tests the event-as-string parsing fix.
///
/// Run with: dart tests/server/hello_local_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/station.dart';
import '../../lib/cli/pure_storage_config.dart';
import '../../lib/util/nostr_event.dart';
import '../../lib/util/nostr_key_generator.dart';
import '../../lib/util/nostr_crypto.dart';

const int TEST_PORT = 45702;
const String WS_URL = 'ws://localhost:$TEST_PORT';

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

Future<void> main() async {
  print('');
  print('=' * 60);
  print('Local HELLO Handshake Test (Event Parsing Fix)');
  print('=' * 60);
  print('');

  // Create temp directory
  final tempDir = await Directory.systemTemp.createTemp('geogram_hello_test_');
  print('Using temp directory: ${tempDir.path}');
  print('Server port: $TEST_PORT');
  print('');

  late StationServer station;
  late NostrKeys testKeys;

  try {
    // Initialize storage config
    PureStorageConfig().reset();
    await PureStorageConfig().init(customBaseDir: tempDir.path);

    // Create and configure server
    station = StationServer();
    station.quietMode = true;
    await station.initialize();
    station.setSetting('httpPort', TEST_PORT);

    // Generate test keys
    testKeys = NostrKeyGenerator.generateKeyPair();
    print('Test identity: ${testKeys.callsign}');
    print('Station: ${station.settings.callsign}');

    // Start server
    print('Starting server...');
    final started = await station.start();
    if (!started) {
      print('ERROR: Failed to start station server');
      exit(1);
    }
    await Future.delayed(const Duration(milliseconds: 500));
    print('Server started successfully');
    print('');

    // Run tests
    await testHelloWithEventAsMap(testKeys, station.settings.callsign);
    await testHelloWithEventAsString(testKeys, station.settings.callsign);
    await testHelloWithEventAsDynamicMap(testKeys, station.settings.callsign);
    await testHelloWithMinimalEvent(testKeys, station.settings.callsign);

    // Cleanup
    print('');
    print('Stopping server...');
    await station.stop();
  } catch (e, stackTrace) {
    print('ERROR: $e');
    print(stackTrace);
    exit(1);
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }

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
    for (final f in _failures) {
      print('  - $f');
    }
    print('');
  }

  exit(_failed > 0 ? 1 : 0);
}

Future<void> testHelloWithEventAsMap(NostrKeys keys, String stationCallsign) async {
  print('Test 1: HELLO with event as Map (normal case)...');
  try {
    final ws = await WebSocket.connect(WS_URL);
    final responseCompleter = Completer<Map<String, dynamic>>();

    ws.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (!responseCompleter.isCompleted) {
        responseCompleter.complete(message);
      }
    });

    // Create and sign event
    final helloEvent = NostrEvent.createHello(
      npub: keys.npub,
      callsign: keys.callsign,
      platform: 'Test',
    );
    helloEvent.calculateId();
    helloEvent.signWithNsec(keys.nsec);

    // Send with event as Map
    ws.add(jsonEncode({
      'type': 'hello',
      'callsign': keys.callsign,
      'event': helloEvent.toJson(),
    }));

    final response = await responseCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => {'error': 'timeout'},
    );

    if (response['type'] == 'hello_ack' && response['success'] == true) {
      pass('Event as Map accepted');
    } else {
      fail('Event as Map', 'Error: ${response['error'] ?? 'unknown'}');
    }

    await ws.close();
  } catch (e) {
    fail('Event as Map', 'Error: $e');
  }
}

Future<void> testHelloWithEventAsString(NostrKeys keys, String stationCallsign) async {
  print('Test 2: HELLO with event as String (double-encoded fix)...');
  try {
    final ws = await WebSocket.connect(WS_URL);
    final responseCompleter = Completer<Map<String, dynamic>>();

    ws.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (!responseCompleter.isCompleted) {
        responseCompleter.complete(message);
      }
    });

    // Create and sign event
    final helloEvent = NostrEvent.createHello(
      npub: keys.npub,
      callsign: keys.callsign,
      platform: 'Test',
    );
    helloEvent.calculateId();
    helloEvent.signWithNsec(keys.nsec);

    // Send with event as STRING (double-encoded) - this was the bug!
    ws.add(jsonEncode({
      'type': 'hello',
      'callsign': keys.callsign,
      'event': jsonEncode(helloEvent.toJson()), // STRING not Map!
    }));

    final response = await responseCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => {'error': 'timeout'},
    );

    if (response['type'] == 'hello_ack' && response['success'] == true) {
      pass('Event as String accepted (fix works!)');
    } else if (response['error'] == 'timeout') {
      fail('Event as String', 'Timeout - fix not working');
    } else {
      fail('Event as String', 'Error: ${response['error'] ?? 'unknown'}');
    }

    await ws.close();
  } catch (e) {
    fail('Event as String', 'Error: $e');
  }
}

Future<void> testHelloWithEventAsDynamicMap(NostrKeys keys, String stationCallsign) async {
  print('Test 3: HELLO with event as dynamic Map...');
  try {
    final ws = await WebSocket.connect(WS_URL);
    final responseCompleter = Completer<Map<String, dynamic>>();

    ws.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (!responseCompleter.isCompleted) {
        responseCompleter.complete(message);
      }
    });

    // Get pubkey hex
    final pubkeyHex = NostrCrypto.decodeNpub(keys.npub);

    // Send with dynamically created Map (simulates JSON parse result)
    final dynamicEvent = <dynamic, dynamic>{
      'pubkey': pubkeyHex,
      'tags': [['callsign', keys.callsign]],
    };

    ws.add(jsonEncode({
      'type': 'hello',
      'callsign': keys.callsign,
      'event': dynamicEvent,
    }));

    final response = await responseCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => {'error': 'timeout'},
    );

    if (response['type'] == 'hello_ack' && response['success'] == true) {
      pass('Dynamic Map event accepted');
    } else {
      fail('Dynamic Map event', 'Error: ${response['error'] ?? 'unknown'}');
    }

    await ws.close();
  } catch (e) {
    fail('Dynamic Map event', 'Error: $e');
  }
}

Future<void> testHelloWithMinimalEvent(NostrKeys keys, String stationCallsign) async {
  print('Test 4: HELLO with minimal event (pubkey only)...');
  try {
    final ws = await WebSocket.connect(WS_URL);
    final responseCompleter = Completer<Map<String, dynamic>>();

    ws.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (!responseCompleter.isCompleted) {
        responseCompleter.complete(message);
      }
    });

    // Get pubkey hex
    final pubkeyHex = NostrCrypto.decodeNpub(keys.npub);

    // Send with minimal event
    ws.add(jsonEncode({
      'type': 'hello',
      'callsign': keys.callsign,
      'event': {'pubkey': pubkeyHex},
    }));

    final response = await responseCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => {'error': 'timeout'},
    );

    if (response['type'] == 'hello_ack' && response['success'] == true) {
      pass('Minimal event accepted');
    } else {
      fail('Minimal event', 'Error: ${response['error'] ?? 'unknown'}');
    }

    await ws.close();
  } catch (e) {
    fail('Minimal event', 'Error: $e');
  }
}
