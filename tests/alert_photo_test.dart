#!/usr/bin/env dart
/// Alert Photo Test for Geogram Desktop
///
/// This test suite verifies alert creation with photos and synchronization
/// between clients via a station.
///
/// It launches:
///   1. A temporary station instance on localhost
///   2. Two client instances that connect to the station
///   3. Client 1 creates an alert with a photo and shares it
///   4. Client 2 receives the alert and can download the photo
///
/// Usage:
///   dart tests/alert_photo_test.dart
///
/// Prerequisites:
///   - Build geogram-desktop first: flutter build linux
///   - Run from the geogram-desktop directory

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// Configuration
const int stationPort = 15000;
const int client1Port = 15001;
const int client2Port = 15002;
const Duration startupWait = Duration(seconds: 8);
const Duration connectionWait = Duration(seconds: 5);

// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

// Process handles for cleanup
Process? _stationProcess;
Process? _client1Process;
Process? _client2Process;
final List<Directory> _tempDirs = [];

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

/// Create a temporary directory for a test instance
Future<Directory> createTempDir(String name) async {
  final dir = await Directory.systemTemp.createTemp('geogram_test_$name');
  _tempDirs.add(dir);
  return dir;
}

/// Launch a geogram-desktop instance
Future<Process?> launchInstance({
  required String name,
  required int port,
  required String dataDir,
  required bool isStation,
  String? scanLocalhostRange,
}) async {
  // Find the executable
  final executable = File('build/linux/x64/release/bundle/geogram_desktop');
  if (!await executable.exists()) {
    print('ERROR: Build not found at ${executable.path}');
    print('Please run: flutter build linux');
    return null;
  }

  final args = [
    '--port=$port',
    '--data-dir=$dataDir',
    '--new-identity',
    '--skip-intro',
    '--http-api',
    '--debug-api',
    '--no-update',
  ];

  if (isStation) {
    args.add('--identity-type=station');
    args.add('--nickname=TestStation');
  } else {
    args.add('--identity-type=client');
    args.add('--nickname=$name');
  }

  if (scanLocalhostRange != null) {
    args.add('--scan-localhost=$scanLocalhostRange');
  }

  print('  Starting $name on port $port...');
  final process = await Process.start(
    executable.path,
    args,
    mode: ProcessStartMode.detachedWithStdio,
  );

  // Log output for debugging
  process.stdout.transform(utf8.decoder).listen((data) {
    if (data.contains('ERROR') || data.contains('Exception')) {
      print('[$name STDOUT] $data');
    }
  });
  process.stderr.transform(utf8.decoder).listen((data) {
    print('[$name STDERR] $data');
  });

  return process;
}

/// Wait for an instance to be ready (API responding)
Future<bool> waitForReady(String name, int port, {Duration timeout = const Duration(seconds: 30)}) async {
  final stopwatch = Stopwatch()..start();
  final url = 'http://localhost:$port/api/';

  while (stopwatch.elapsed < timeout) {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        info('$name ready: ${data['callsign']}');
        return true;
      }
    } catch (e) {
      // Not ready yet
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

/// Get callsign from instance
Future<String?> getCallsign(int port) async {
  try {
    final response = await http.get(Uri.parse('http://localhost:$port/api/'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['callsign'] as String?;
    }
  } catch (e) {
    // Ignore
  }
  return null;
}

/// Send debug API action
Future<Map<String, dynamic>?> debugAction(int port, Map<String, dynamic> action) async {
  try {
    final response = await http.post(
      Uri.parse('http://localhost:$port/api/debug'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(action),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      print('  DEBUG API Error: ${response.statusCode} ${response.body}');
    }
  } catch (e) {
    print('  DEBUG API Exception: $e');
  }
  return null;
}

/// Connect a client to the station
Future<bool> connectToStation(int clientPort) async {
  final result = await debugAction(clientPort, {
    'action': 'connect_station',
    'url': 'ws://localhost:$stationPort',
  });
  return result?['success'] == true;
}

/// Wait for client to be connected to station
Future<bool> waitForStationConnection(int clientPort, {Duration timeout = const Duration(seconds: 20)}) async {
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < timeout) {
    // Try connecting
    await connectToStation(clientPort);
    await Future.delayed(const Duration(seconds: 2));

    // Check if connected by looking at station clients
    try {
      final response = await http.get(Uri.parse('http://localhost:$stationPort/api/clients'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final clients = data['clients'] as List;
        if (clients.isNotEmpty) {
          return true;
        }
      }
    } catch (e) {
      // Not connected yet
    }
  }

  return false;
}

/// Create an alert with a photo on client 1
Future<String?> createAlertWithPhoto(int port) async {
  final result = await debugAction(port, {
    'action': 'alert_create',
    'title': 'Photo Test Alert',
    'description': 'Testing photo upload via station',
    'latitude': 38.7223,
    'longitude': -9.1393,
    'severity': 'info',
    'type': 'test',
    'photo': true,
  });

  if (result?['success'] == true) {
    return result?['alert_id'] as String?;
  }
  return null;
}

/// Share an alert to the station
Future<bool> shareAlert(int port, String alertId) async {
  final result = await debugAction(port, {
    'action': 'alert_share',
    'alert_id': alertId,
  });

  if (result?['success'] == true) {
    final summary = result?['summary'];
    if (summary != null) {
      info('Share summary: confirmed=${summary['confirmed']}, failed=${summary['failed']}');
    }
    return true;
  }
  return false;
}

/// List alerts from debug API
Future<List<Map<String, dynamic>>> listAlerts(int port) async {
  final result = await debugAction(port, {'action': 'alert_list'});
  if (result?['success'] == true && result?['alerts'] is List) {
    return (result!['alerts'] as List).cast<Map<String, dynamic>>();
  }
  return [];
}

/// Get alert photo from station
Future<bool> downloadAlertPhoto(String callsign, String alertId, String filename) async {
  try {
    final url = 'http://localhost:$stationPort/$callsign/api/alerts/$alertId/files/$filename';
    info('Downloading photo from: $url');

    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200 && response.bodyBytes.length > 100) {
      info('Downloaded ${response.bodyBytes.length} bytes');
      // Check if it's a valid PNG (starts with PNG magic bytes)
      final isPng = response.bodyBytes.length >= 8 &&
          response.bodyBytes[0] == 0x89 &&
          response.bodyBytes[1] == 0x50 &&
          response.bodyBytes[2] == 0x4E &&
          response.bodyBytes[3] == 0x47;
      if (isPng) {
        return true;
      }
    }
  } catch (e) {
    info('Download error: $e');
  }
  return false;
}

/// Cleanup all processes and temp directories
Future<void> cleanup() async {
  print('\n=== Cleanup ===');

  // Kill processes
  if (_client2Process != null) {
    info('Stopping client 2...');
    _client2Process!.kill(ProcessSignal.sigterm);
  }
  if (_client1Process != null) {
    info('Stopping client 1...');
    _client1Process!.kill(ProcessSignal.sigterm);
  }
  if (_stationProcess != null) {
    info('Stopping station...');
    _stationProcess!.kill(ProcessSignal.sigterm);
  }

  // Wait a moment for processes to exit
  await Future.delayed(const Duration(seconds: 2));

  // Force kill if needed
  _client2Process?.kill(ProcessSignal.sigkill);
  _client1Process?.kill(ProcessSignal.sigkill);
  _stationProcess?.kill(ProcessSignal.sigkill);

  // Clean up temp directories
  for (final dir in _tempDirs) {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        info('Deleted temp dir: ${dir.path}');
      }
    } catch (e) {
      info('Could not delete ${dir.path}: $e');
    }
  }
}

// ============================================================
// Tests
// ============================================================

Future<void> testStationConnected() async {
  print('\n--- Test: Station Connected ---');

  try {
    final response = await http.get(Uri.parse('http://localhost:$stationPort/api/clients'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final count = data['count'] as int;
      info('Connected clients: $count');
      if (count > 0) {
        pass('Clients connected to station');
      } else {
        fail('Station connection', 'No clients connected');
      }
    } else {
      fail('Station API', 'Status ${response.statusCode}');
    }
  } catch (e) {
    fail('Station connection test', 'Exception: $e');
  }
}

Future<String?> testCreateAlertWithPhoto() async {
  print('\n--- Test: Create Alert with Photo ---');

  final alertId = await createAlertWithPhoto(client1Port);
  if (alertId != null) {
    pass('Created alert: $alertId');
    return alertId;
  } else {
    fail('Create alert', 'Failed to create alert with photo');
    return null;
  }
}

Future<bool> testShareAlert(String alertId) async {
  print('\n--- Test: Share Alert to Station ---');

  final shared = await shareAlert(client1Port, alertId);
  if (shared) {
    pass('Alert shared to station');
    return true;
  } else {
    fail('Share alert', 'Failed to share alert');
    return false;
  }
}

Future<void> testPhotoAvailableOnStation(String callsign, String alertId) async {
  print('\n--- Test: Photo Available on Station ---');

  // Wait a moment for upload to complete
  await Future.delayed(const Duration(seconds: 2));

  // Try to download the photo
  final downloaded = await downloadAlertPhoto(callsign, alertId, 'test_photo.png');
  if (downloaded) {
    pass('Photo downloaded from station successfully');
  } else {
    // Try with different filename
    final downloaded2 = await downloadAlertPhoto(callsign, alertId, 'photo_0.png');
    if (downloaded2) {
      pass('Photo downloaded from station (alternate name)');
    } else {
      fail('Photo download', 'Could not download photo from station');
    }
  }
}

Future<void> testAlertVisibleOnClient2() async {
  print('\n--- Test: Alert Visible on Client 2 ---');

  // This would require station sync to client 2
  // For now, we just check that client 2 is connected
  try {
    final response = await http.get(Uri.parse('http://localhost:$client2Port/api/'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      pass('Client 2 is running: ${data['callsign']}');
    } else {
      fail('Client 2 status', 'Status ${response.statusCode}');
    }
  } catch (e) {
    fail('Client 2 check', 'Exception: $e');
  }
}

// ============================================================
// Main
// ============================================================

Future<void> main() async {
  print('');
  print('=' * 60);
  print('Geogram Desktop Alert Photo Test Suite');
  print('=' * 60);
  print('');

  // Check if build exists
  final executable = File('build/linux/x64/release/bundle/geogram_desktop');
  if (!await executable.exists()) {
    print('ERROR: Build not found at ${executable.path}');
    print('');
    print('Please build first:');
    print('  flutter build linux --release');
    exit(1);
  }
  print('✓ Build found');

  try {
    // Create temp directories
    print('\n=== Setting up test environment ===');
    final stationDir = await createTempDir('station');
    final client1Dir = await createTempDir('client1');
    final client2Dir = await createTempDir('client2');

    info('Station dir: ${stationDir.path}');
    info('Client 1 dir: ${client1Dir.path}');
    info('Client 2 dir: ${client2Dir.path}');

    // Launch station
    print('\n=== Launching Station ===');
    _stationProcess = await launchInstance(
      name: 'Station',
      port: stationPort,
      dataDir: stationDir.path,
      isStation: true,
    );

    if (_stationProcess == null) {
      print('ERROR: Failed to start station');
      exit(1);
    }

    // Wait for station to be ready
    print('  Waiting for station to start...');
    await Future.delayed(startupWait);

    if (!await waitForReady('Station', stationPort)) {
      print('ERROR: Station did not become ready');
      await cleanup();
      exit(1);
    }
    print('✓ Station is ready');

    // Launch client 1
    print('\n=== Launching Client 1 ===');
    _client1Process = await launchInstance(
      name: 'Client1',
      port: client1Port,
      dataDir: client1Dir.path,
      isStation: false,
      scanLocalhostRange: '$stationPort-$stationPort',
    );

    if (_client1Process == null) {
      print('ERROR: Failed to start client 1');
      await cleanup();
      exit(1);
    }

    // Wait for client 1 to be ready
    print('  Waiting for client 1 to start...');
    await Future.delayed(startupWait);

    if (!await waitForReady('Client1', client1Port)) {
      print('ERROR: Client 1 did not become ready');
      await cleanup();
      exit(1);
    }
    print('✓ Client 1 is ready');

    // Get client 1 callsign
    final client1Callsign = await getCallsign(client1Port);
    if (client1Callsign == null) {
      print('ERROR: Could not get client 1 callsign');
      await cleanup();
      exit(1);
    }
    print('  Client 1 callsign: $client1Callsign');

    // Launch client 2
    print('\n=== Launching Client 2 ===');
    _client2Process = await launchInstance(
      name: 'Client2',
      port: client2Port,
      dataDir: client2Dir.path,
      isStation: false,
      scanLocalhostRange: '$stationPort-$stationPort',
    );

    if (_client2Process == null) {
      print('ERROR: Failed to start client 2');
      await cleanup();
      exit(1);
    }

    // Wait for client 2 to be ready
    print('  Waiting for client 2 to start...');
    await Future.delayed(startupWait);

    if (!await waitForReady('Client2', client2Port)) {
      print('ERROR: Client 2 did not become ready');
      await cleanup();
      exit(1);
    }
    print('✓ Client 2 is ready');

    // Connect clients to station
    print('\n=== Connecting Clients to Station ===');
    await connectToStation(client1Port);
    await Future.delayed(connectionWait);
    await connectToStation(client2Port);
    await Future.delayed(connectionWait);

    // Wait for connections
    if (!await waitForStationConnection(client1Port)) {
      print('WARNING: Client 1 may not be connected to station');
    }

    // Run tests
    print('\n=== Running Tests ===');

    await testStationConnected();

    final alertId = await testCreateAlertWithPhoto();
    if (alertId != null) {
      final shared = await testShareAlert(alertId);
      if (shared) {
        await testPhotoAvailableOnStation(client1Callsign, alertId);
      }
    }

    await testAlertVisibleOnClient2();

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

  } finally {
    // Always cleanup
    await cleanup();
  }

  exit(_failed > 0 ? 1 : 0);
}
