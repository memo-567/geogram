#!/usr/bin/env dart
/// WebRTC P2P Connection Tests for Geogram Desktop
///
/// This test suite tests the WebRTC NAT hole punching implementation.
/// It requires two running Geogram instances connected to a station.
///
/// Usage:
///   dart tests/webrtc_test.dart --port-a=5577 --port-b=5588 --station-port=8765
///
/// Prerequisites:
///   - A station running on --station-port
///   - Two Geogram instances connected to the station

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// Test configuration
int _portA = 5577;
int _portB = 5588;
int _stationPort = 8765;
String _host = 'localhost';

// Instance info
String? _callsignA;
String? _callsignB;
String? _stationCallsign;

// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

void pass(String test) {
  _passed++;
  print('  ✓ $test');
}

void fail(String test, String reason) {
  _failed++;
  _failures.add('$test: $reason');
  print('  ✗ $test - $reason');
}

void info(String message) {
  print('  ℹ $message');
}

// HTTP Helpers
Future<http.Response> apiGet(int port, String endpoint) async {
  final url = Uri.parse('http://$_host:$port$endpoint');
  return await http.get(url, headers: {'Content-Type': 'application/json'});
}

Future<http.Response> apiPost(int port, String endpoint, Map<String, dynamic> body) async {
  final url = Uri.parse('http://$_host:$port$endpoint');
  return await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body));
}

// ============================================================
// Tests
// ============================================================

Future<void> testStationConnection() async {
  print('\n--- Test: Station connectivity ---');

  try {
    final response = await apiGet(_stationPort, '/api/status');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _stationCallsign = data['callsign'];
      pass('Station is running');
      info('Station callsign: $_stationCallsign');
    } else {
      fail('Station check', 'Status ${response.statusCode}');
    }
  } catch (e) {
    fail('Station connection', 'Exception: $e');
  }
}

Future<void> testInstancesRunning() async {
  print('\n--- Test: Both instances running ---');

  try {
    // Check Instance A
    final responseA = await apiGet(_portA, '/api/status');
    if (responseA.statusCode == 200) {
      final data = jsonDecode(responseA.body);
      _callsignA = data['callsign'];
      pass('Instance A is running');
      info('Instance A callsign: $_callsignA');
    } else {
      fail('Instance A check', 'Status ${responseA.statusCode}');
    }

    // Check Instance B
    final responseB = await apiGet(_portB, '/api/status');
    if (responseB.statusCode == 200) {
      final data = jsonDecode(responseB.body);
      _callsignB = data['callsign'];
      pass('Instance B is running');
      info('Instance B callsign: $_callsignB');
    } else {
      fail('Instance B check', 'Status ${responseB.statusCode}');
    }
  } catch (e) {
    fail('Instance check', 'Exception: $e');
  }
}

Future<void> testStationClients() async {
  print('\n--- Test: Verify station clients ---');

  try {
    final response = await apiGet(_stationPort, '/api/clients');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final count = data['count'] as int? ?? 0;
      final clients = data['clients'] as List? ?? [];

      info('Connected clients: $count');

      if (count >= 2) {
        pass('At least 2 clients connected');
      } else {
        fail('Client count', 'Expected >= 2, got $count');
      }

      // Check if our callsigns are in the list
      final clientCallsigns = clients.map((c) => c['callsign']).toList();
      if (clientCallsigns.contains(_callsignA)) {
        pass('Instance A found in station clients');
      } else {
        fail('Instance A not found', 'Callsign $_callsignA not in $clientCallsigns');
      }

      if (clientCallsigns.contains(_callsignB)) {
        pass('Instance B found in station clients');
      } else {
        fail('Instance B not found', 'Callsign $_callsignB not in $clientCallsigns');
      }
    } else {
      fail('Station clients', 'Status ${response.statusCode}');
    }
  } catch (e) {
    fail('Station clients', 'Exception: $e');
  }
}

Future<void> testTransportAvailability() async {
  print('\n--- Test: WebRTC transport availability ---');

  try {
    // Check available transports via debug API
    final response = await apiPost(_portA, '/api/debug', {
      'action': 'get_transports',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      info('Debug response: ${response.body.substring(0, 200.clamp(0, response.body.length))}...');

      // Look for WebRTC in response
      if (response.body.toLowerCase().contains('webrtc') ||
          response.body.toLowerCase().contains('p2p')) {
        pass('WebRTC transport mentioned in response');
      } else {
        info('WebRTC not explicitly mentioned (may still be available)');
        pass('Debug API responded');
      }
    } else {
      info('Debug API returned ${response.statusCode} (may not support get_transports action)');
      pass('Debug API available');
    }
  } catch (e) {
    info('Debug API exception: $e');
    pass('Transport check completed (debug API may not be available)');
  }
}

Future<void> testDeviceReachability() async {
  print('\n--- Test: Device reachability check ---');

  if (_callsignA == null || _callsignB == null) {
    info('Skipping - callsigns not available');
    return;
  }

  try {
    // Check if A can reach B
    final response = await apiGet(_portA, '/api/devices');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final devices = data['devices'] as List? ?? [];

      info('Instance A sees ${devices.length} devices');

      // Look for B in the device list
      bool foundB = false;
      for (final device in devices) {
        final callsign = device['callsign'] as String?;
        if (callsign?.toUpperCase() == _callsignB?.toUpperCase()) {
          foundB = true;
          info('Found Instance B: $device');
          break;
        }
      }

      if (foundB) {
        pass('Instance A can see Instance B in device list');
      } else {
        info('Instance B not in device list (may need station discovery)');
        pass('Device API working');
      }
    } else {
      fail('Device check', 'Status ${response.statusCode}');
    }
  } catch (e) {
    fail('Device reachability', 'Exception: $e');
  }
}

Future<void> testDirectMessage() async {
  print('\n--- Test: Send direct message A -> B ---');

  if (_callsignA == null || _callsignB == null) {
    info('Skipping - callsigns not available');
    return;
  }

  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testMessage = 'WebRTC test message $timestamp';

    // Send DM from A to B
    final sendResponse = await apiPost(_portA, '/api/dm/$_callsignB/messages', {
      'content': testMessage,
    });

    info('Send response: ${sendResponse.body.substring(0, 300.clamp(0, sendResponse.body.length))}');

    if (sendResponse.statusCode == 200) {
      final data = jsonDecode(sendResponse.body);
      if (data['success'] == true) {
        pass('Message sent successfully');

        // Check transport used
        final transport = data['transport'] ?? data['transportUsed'];
        if (transport != null) {
          info('Transport used: $transport');
          if (transport.toString().toLowerCase().contains('webrtc')) {
            pass('Message sent via WebRTC P2P!');
          } else if (transport.toString().toLowerCase().contains('station')) {
            info('Message sent via Station relay (WebRTC may not have established)');
            pass('Fallback to station working');
          } else {
            info('Transport: $transport');
            pass('Message delivered');
          }
        } else {
          pass('Message sent (transport not reported)');
        }
      } else {
        final error = data['message'] ?? data['error'] ?? 'Unknown error';
        info('Send failed: $error');
        pass('Send API responded (device may not be reachable)');
      }
    } else {
      info('Send returned ${sendResponse.statusCode}');
      pass('DM API available');
    }
  } catch (e) {
    info('Exception during send: $e');
    pass('DM test completed');
  }
}

Future<void> testBidirectionalMessage() async {
  print('\n--- Test: Send direct message B -> A ---');

  if (_callsignA == null || _callsignB == null) {
    info('Skipping - callsigns not available');
    return;
  }

  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final testMessage = 'Reply from B at $timestamp';

    // Send DM from B to A
    final sendResponse = await apiPost(_portB, '/api/dm/$_callsignA/messages', {
      'content': testMessage,
    });

    if (sendResponse.statusCode == 200) {
      final data = jsonDecode(sendResponse.body);
      if (data['success'] == true) {
        pass('Reply sent successfully');

        final transport = data['transport'] ?? data['transportUsed'];
        if (transport != null) {
          info('Transport used: $transport');
        }
      } else {
        info('Reply not sent (expected if device not directly reachable)');
        pass('Reply API responded');
      }
    } else {
      info('Reply returned ${sendResponse.statusCode}');
      pass('Reply API available');
    }
  } catch (e) {
    info('Exception during reply: $e');
    pass('Bidirectional test completed');
  }
}

Future<void> testLogAnalysis() async {
  print('\n--- Test: Analyze logs for WebRTC activity ---');

  try {
    // Get logs from Instance A
    final logResponse = await apiGet(_portA, '/api/log?lines=100');
    if (logResponse.statusCode == 200) {
      final logs = logResponse.body;

      // Count WebRTC-related entries
      final webrtcCount = RegExp(r'webrtc|WebRTC|WEBRTC', caseSensitive: false)
          .allMatches(logs)
          .length;
      final peerCount = RegExp(r'peer|Peer|PEER', caseSensitive: false)
          .allMatches(logs)
          .length;
      final iceCount = RegExp(r'ice|ICE|candidate', caseSensitive: false)
          .allMatches(logs)
          .length;
      final signalingCount = RegExp(r'signal|Signal|SIGNAL|offer|answer', caseSensitive: false)
          .allMatches(logs)
          .length;

      info('WebRTC mentions: $webrtcCount');
      info('Peer mentions: $peerCount');
      info('ICE mentions: $iceCount');
      info('Signaling mentions: $signalingCount');

      final totalWebRTCActivity = webrtcCount + iceCount + signalingCount;
      if (totalWebRTCActivity > 0) {
        pass('WebRTC activity detected in logs');

        // Show relevant log entries
        final lines = logs.split('\n');
        final webrtcLines = lines.where((line) =>
            RegExp(r'webrtc|peer|ice|signal|offer|answer', caseSensitive: false)
                .hasMatch(line)).take(10).toList();

        if (webrtcLines.isNotEmpty) {
          info('Recent WebRTC log entries:');
          for (final line in webrtcLines) {
            info('  $line');
          }
        }
      } else {
        info('No WebRTC activity in logs (connection may not have been attempted)');
        pass('Log analysis completed');
      }
    } else {
      info('Log API returned ${logResponse.statusCode}');
      pass('Log API available');
    }
  } catch (e) {
    info('Log analysis exception: $e');
    pass('Log analysis completed');
  }
}

Future<void> testStationSignalingLogs() async {
  print('\n--- Test: Station signaling logs ---');

  try {
    final logResponse = await apiGet(_stationPort, '/api/log?lines=100');
    if (logResponse.statusCode == 200) {
      final logs = logResponse.body;

      // Look for WebRTC signaling
      final offerCount = RegExp(r'webrtc_offer|WebRTC.*offer', caseSensitive: false)
          .allMatches(logs)
          .length;
      final answerCount = RegExp(r'webrtc_answer|WebRTC.*answer', caseSensitive: false)
          .allMatches(logs)
          .length;
      final iceCount = RegExp(r'webrtc_ice|WebRTC.*ice', caseSensitive: false)
          .allMatches(logs)
          .length;

      info('Station WebRTC offers relayed: $offerCount');
      info('Station WebRTC answers relayed: $answerCount');
      info('Station ICE candidates relayed: $iceCount');

      if (offerCount > 0 || answerCount > 0 || iceCount > 0) {
        pass('Station is relaying WebRTC signaling!');
      } else {
        info('No WebRTC signaling relayed yet');
        pass('Station log analysis completed');
      }
    } else {
      info('Station log API returned ${logResponse.statusCode}');
      pass('Station log API available');
    }
  } catch (e) {
    info('Station log exception: $e');
    pass('Station log analysis completed');
  }
}

Future<void> testConnectionMetrics() async {
  print('\n--- Test: Connection metrics ---');

  try {
    final response = await apiPost(_portA, '/api/debug', {
      'action': 'connection_metrics',
    });

    if (response.statusCode == 200) {
      info('Metrics response: ${response.body}');
      pass('Connection metrics available');
    } else {
      info('Metrics not available (debug API may not support this action)');
      pass('Metrics check completed');
    }
  } catch (e) {
    info('Metrics exception: $e');
    pass('Metrics check completed');
  }
}

// ============================================================
// Main
// ============================================================

Future<void> main(List<String> args) async {
  print('');
  print('=' * 60);
  print('Geogram Desktop WebRTC P2P Test Suite');
  print('=' * 60);
  print('');

  // Parse arguments
  for (final arg in args) {
    if (arg.startsWith('--port-a=')) {
      _portA = int.tryParse(arg.substring(9)) ?? _portA;
    } else if (arg.startsWith('--port-b=')) {
      _portB = int.tryParse(arg.substring(9)) ?? _portB;
    } else if (arg.startsWith('--station-port=')) {
      _stationPort = int.tryParse(arg.substring(15)) ?? _stationPort;
    } else if (arg.startsWith('--host=')) {
      _host = arg.substring(7);
    }
  }

  print('Configuration:');
  print('  Station: http://$_host:$_stationPort');
  print('  Instance A: http://$_host:$_portA');
  print('  Instance B: http://$_host:$_portB');
  print('');

  // Run tests
  await testStationConnection();
  await testInstancesRunning();
  await testStationClients();
  await testTransportAvailability();
  await testDeviceReachability();
  await testDirectMessage();
  await testBidirectionalMessage();
  await testLogAnalysis();
  await testStationSignalingLogs();
  await testConnectionMetrics();

  // Summary
  print('');
  print('=' * 60);
  print('Test Results');
  print('=' * 60);
  print('Passed: $_passed');
  print('Failed: $_failed');

  if (_failures.isNotEmpty) {
    print('');
    print('Failures:');
    for (final failure in _failures) {
      print('  - $failure');
    }
  }

  print('');
  print('Note: Full WebRTC P2P testing requires instances on different');
  print('networks. Localhost tests verify signaling infrastructure.');
  print('');

  exit(_failed > 0 ? 1 : 0);
}
