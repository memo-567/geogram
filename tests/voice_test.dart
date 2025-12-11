#!/usr/bin/env dart
/// Voice Recording API Test for Geogram Desktop
///
/// This test verifies that voice recording works on Linux via the debug API.
/// It launches a temporary instance, records audio, and verifies the file is saved.
///
/// Usage:
///   dart tests/voice_test.dart
///
/// Prerequisites:
///   - Linux build available at build/linux/x64/release/bundle/geogram_desktop
///   - Working microphone (or at least ALSA available)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Test configuration
const int _testPort = 5599;
const String _testHost = 'localhost';
const String _testDataDir = '/tmp/geogram-voice-test';
const String _binaryPath = 'build/linux/x64/release/bundle/geogram_desktop';
const int _recordDuration = 3; // seconds

// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

void pass(String test) {
  _passed++;
  print('  \u2713 $test');
}

void fail(String test, String reason) {
  _failed++;
  _failures.add('$test: $reason');
  print('  \u2717 $test - $reason');
}

void info(String message) {
  print('  \u2139 $message');
}

// HTTP client for API calls
Future<Map<String, dynamic>?> apiGet(String endpoint) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://$_testHost:$_testPort$endpoint'));
    request.headers.contentType = ContentType.json;
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    return null;
  }
}

Future<Map<String, dynamic>?> apiPost(String endpoint, Map<String, dynamic> data) async {
  try {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('http://$_testHost:$_testPort$endpoint'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    print('  ! API POST error: $e');
    return null;
  }
}

/// Wait for server to be ready
Future<bool> waitForServer({int maxAttempts = 30}) async {
  for (var i = 0; i < maxAttempts; i++) {
    final response = await apiGet('/api/status');
    if (response != null && response['callsign'] != null) {
      return true;
    }
    await Future.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// Test: Check debug API is available
Future<void> testDebugApiAvailable() async {
  print('\n--- Test: Debug API Available ---');

  final response = await apiGet('/api/debug');
  if (response == null) {
    fail('Debug API', 'No response from /api/debug');
    return;
  }

  final actions = response['available_actions'] as List<dynamic>?;
  if (actions == null) {
    fail('Debug API', 'Missing available_actions in response');
    return;
  }

  // Check for voice actions
  final actionNames = actions.map((a) => a['action']).toList();
  if (actionNames.contains('voice_record')) {
    pass('voice_record action available');
  } else {
    fail('voice_record', 'Action not found in available_actions');
  }

  if (actionNames.contains('voice_stop')) {
    pass('voice_stop action available');
  } else {
    fail('voice_stop', 'Action not found in available_actions');
  }

  if (actionNames.contains('voice_status')) {
    pass('voice_status action available');
  } else {
    fail('voice_status', 'Action not found in available_actions');
  }

  info('Found ${actions.length} total debug actions');
}

/// Test: Check voice status (should be idle)
Future<void> testVoiceStatus() async {
  print('\n--- Test: Voice Status (Idle) ---');

  final response = await apiPost('/api/debug', {'action': 'voice_status'});
  if (response == null) {
    fail('Voice status', 'No response');
    return;
  }

  if (response['success'] == true) {
    pass('Voice status returned successfully');
    info('is_recording: ${response['is_recording']}');
    info('is_playing: ${response['is_playing']}');

    if (response['is_recording'] == false) {
      pass('Not recording initially');
    } else {
      fail('Initial state', 'Expected is_recording=false');
    }
  } else {
    fail('Voice status', 'Response: ${response['error']}');
  }
}

/// Test: Record audio for specified duration
Future<String?> testVoiceRecord() async {
  print('\n--- Test: Voice Recording ($_recordDuration seconds) ---');

  info('Starting recording...');
  final response = await apiPost('/api/debug', {
    'action': 'voice_record',
    'duration': _recordDuration,
  });

  if (response == null) {
    fail('Voice record', 'No response (timeout?)');
    return null;
  }

  if (response['success'] != true) {
    fail('Voice record', 'Error: ${response['error']}');
    return null;
  }

  pass('Recording completed');
  info('file_path: ${response['file_path']}');
  info('file_exists: ${response['file_exists']}');
  info('file_size: ${response['file_size']} bytes');
  info('duration_recorded: ${response['duration_recorded']}s');

  if (response['file_exists'] != true) {
    fail('File creation', 'file_exists is false');
    return null;
  }

  final fileSize = response['file_size'] as int? ?? 0;
  if (fileSize > 0) {
    pass('Audio file has content ($fileSize bytes)');
  } else {
    fail('File content', 'file_size is 0');
    return null;
  }

  return response['file_path'] as String?;
}

/// Test: Verify file exists on disk
Future<void> testFileOnDisk(String filePath) async {
  print('\n--- Test: Verify File on Disk ---');

  final file = File(filePath);
  if (await file.exists()) {
    pass('File exists at: $filePath');

    final stat = await file.stat();
    info('File size: ${stat.size} bytes');
    info('Modified: ${stat.modified}');

    // Check it's an OGG file (starts with OggS)
    final bytes = await file.readAsBytes();
    if (bytes.length >= 4) {
      final magic = String.fromCharCodes(bytes.sublist(0, 4));
      if (magic == 'OggS') {
        pass('Valid OGG container (OggS magic)');
      } else {
        info('File magic: ${bytes.sublist(0, 4)}');
        // On Linux we create OGG/Opus, on other platforms might be different
        if (filePath.endsWith('.ogg')) {
          fail('OGG magic', 'Expected OggS, got: $magic');
        } else {
          info('Non-OGG format detected (platform specific)');
          pass('Audio file created (platform format)');
        }
      }
    }
  } else {
    fail('File exists', 'File not found: $filePath');
  }
}

/// Cleanup: Kill the test instance and remove temp data
Future<void> cleanup(Process? process) async {
  print('\n--- Cleanup ---');

  if (process != null) {
    info('Killing test instance...');
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
    pass('Test instance terminated');
  }

  // Clean up temp directory
  final tempDir = Directory(_testDataDir);
  if (await tempDir.exists()) {
    try {
      await tempDir.delete(recursive: true);
      pass('Temp directory cleaned: $_testDataDir');
    } catch (e) {
      info('Could not delete temp dir: $e');
    }
  }
}

Future<void> main(List<String> args) async {
  print('');
  print('=' * 60);
  print('Geogram Voice Recording Test');
  print('=' * 60);
  print('');

  // Check if binary exists
  final binary = File(_binaryPath);
  if (!await binary.exists()) {
    print('\u274C Binary not found at: $_binaryPath');
    print('   Run: flutter build linux --release');
    exit(1);
  }
  print('\u2713 Binary found');

  // Create temp data directory
  await Directory(_testDataDir).create(recursive: true);
  print('\u2713 Temp directory created: $_testDataDir');

  Process? process;

  try {
    // Launch test instance
    print('\nLaunching test instance...');
    process = await Process.start(
      _binaryPath,
      [
        '--port=$_testPort',
        '--data-dir=$_testDataDir',
        '--new-identity',
        '--skip-intro',
        '--http-api',
        '--debug-api',
        '--no-update',
      ],
      environment: {'DISPLAY': Platform.environment['DISPLAY'] ?? ':0'},
    );

    // Forward stderr for debugging
    process.stderr.transform(utf8.decoder).listen((data) {
      if (data.contains('Error') || data.contains('error')) {
        print('[STDERR] $data');
      }
    });

    // Wait for server to be ready
    print('Waiting for server to start...');
    final ready = await waitForServer();
    if (!ready) {
      fail('Server startup', 'Timeout waiting for server');
      await cleanup(process);
      exit(1);
    }

    // Get server info
    final status = await apiGet('/api/status');
    print('\u2713 Server started');
    print('  Callsign: ${status?['callsign']}');
    print('  Port: $_testPort');

    // Run tests
    await testDebugApiAvailable();
    await testVoiceStatus();
    final filePath = await testVoiceRecord();
    if (filePath != null) {
      await testFileOnDisk(filePath);
    }

    // Cleanup
    await cleanup(process);
    process = null;

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
    exit(_failed > 0 ? 1 : 0);

  } catch (e, stack) {
    print('\n\u274C Unexpected error: $e');
    print(stack);
    await cleanup(process);
    exit(1);
  }
}
