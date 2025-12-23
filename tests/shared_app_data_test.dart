#!/usr/bin/env dart
/// Geogram Desktop Shared App Data Test Suite
///
/// This test verifies remote device browsing functionality by:
///   - Launching two instances with localhost scanning
///   - Instance A creates a blog post
///   - Instance B discovers Instance A via localhost scan
///   - Instance B can browse Instance A's blog data
///
/// The test launches:
///   - Instance A at /tmp/geogram-shared-test-a (port 17000)
///   - Instance B at /tmp/geogram-shared-test-b (port 17100)
///
/// Usage:
///   dart run tests/shared_app_data_test.dart
///
/// Prerequisites:
///   - Build desktop: flutter build linux --release
///   - Run from the geogram-desktop directory

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// ============================================================
// Configuration
// ============================================================

/// Fixed temp directories for easy debugging and inspection
const String instanceADataDir = '/tmp/geogram-shared-test-a';
const String instanceBDataDir = '/tmp/geogram-shared-test-b';

/// Ports for the instances
const int instanceAPort = 17000;
const int instanceBPort = 17100;

/// Scan range for localhost discovery
const String scanLocalhostRange = '$instanceAPort-$instanceBPort';

/// Timing configuration
const Duration startupWait = Duration(seconds: 15);
const Duration apiWait = Duration(seconds: 2);
const Duration discoveryTimeout = Duration(seconds: 30);

// ============================================================
// Test State
// ============================================================

/// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

/// Process handles for cleanup
Process? _instanceAProcess;
Process? _instanceBProcess;

/// Instance information
String? _instanceACallsign;
String? _instanceBCallsign;
String? _createdBlogId;

// ============================================================
// Output Helpers
// ============================================================

void pass(String test) {
  _passed++;
  print('  \x1B[32m✓\x1B[0m $test');
}

void fail(String test, String reason) {
  _failed++;
  _failures.add('$test: $reason');
  print('  \x1B[31m✗\x1B[0m $test - $reason');
}

void info(String message) {
  print('  \x1B[36mℹ\x1B[0m $message');
}

void warn(String message) {
  print('  \x1B[33m⚠\x1B[0m $message');
}

void section(String title) {
  print('\n\x1B[1m=== $title ===\x1B[0m');
}

// ============================================================
// Instance Management
// ============================================================

/// Launch a geogram-desktop instance
Future<Process?> launchInstance({
  required String name,
  required int port,
  required String dataDir,
  required String scanRange,
}) async {
  // Find the executable
  final executable = File('build/linux/x64/release/bundle/geogram_desktop');
  if (!await executable.exists()) {
    print('ERROR: Build not found at ${executable.path}');
    print('Please run: flutter build linux --release');
    return null;
  }

  final args = [
    '--port=$port',
    '--data-dir=$dataDir',
    '--new-identity',
    '--nickname=$name',
    '--skip-intro',
    '--http-api',
    '--debug-api',
    '--scan-localhost=$scanRange',
  ];

  info('Starting $name on port $port...');
  info('Data directory: $dataDir');
  info('Scan range: $scanRange');

  final process = await Process.start(
    executable.path,
    args,
    mode: ProcessStartMode.detachedWithStdio,
  );

  // Log errors for debugging
  process.stderr.transform(utf8.decoder).listen((data) {
    if (data.trim().isNotEmpty) {
      print('  [$name STDERR] ${data.trim()}');
    }
  });

  return process;
}

/// Wait for an instance to be ready (API responding)
Future<bool> waitForReady(String name, int port,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final stopwatch = Stopwatch()..start();
  final url = 'http://localhost:$port/api/status';

  while (stopwatch.elapsed < timeout) {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        info('$name ready (${data['callsign']})');
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
    final response = await http.get(Uri.parse('http://localhost:$port/api/status'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['callsign'] as String?;
    }
  } catch (e) {
    // Failed
  }
  return null;
}

/// Send debug API action
Future<Map<String, dynamic>?> debugAction(
    int port, Map<String, dynamic> action) async {
  try {
    final response = await http
        .post(
          Uri.parse('http://localhost:$port/api/debug'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(action),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        info('DEBUG API JSON parse error: $e');
        return null;
      }
    } else {
      info('DEBUG API Error (${response.statusCode}): ${response.body}');
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    }
  } catch (e) {
    info('DEBUG API Exception: $e');
    return {'success': false, 'error': 'Exception: $e'};
  }
}

// ============================================================
// Setup and Cleanup
// ============================================================

/// Prepare temp directories (clean and create)
Future<void> prepareDirectories() async {
  for (final path in [instanceADataDir, instanceBDataDir]) {
    // Use shell rm -rf for reliable cleanup
    final rmResult = await Process.run('rm', ['-rf', path]);
    if (rmResult.exitCode != 0) {
      warn('Failed to remove $path: ${rmResult.stderr}');
    } else {
      info('Removed existing directory: $path');
    }

    // Create fresh directory
    final dir = Directory(path);
    await dir.create(recursive: true);
    info('Created directory: $path');
  }
}

/// Cleanup all processes
Future<void> cleanup() async {
  section('Cleanup');

  // Stop instances
  if (_instanceBProcess != null) {
    info('Stopping Instance B...');
    _instanceBProcess!.kill(ProcessSignal.sigterm);
  }

  if (_instanceAProcess != null) {
    info('Stopping Instance A...');
    _instanceAProcess!.kill(ProcessSignal.sigterm);
  }

  // Wait a moment for processes to exit
  await Future.delayed(const Duration(seconds: 2));

  // Force kill if needed
  _instanceBProcess?.kill(ProcessSignal.sigkill);
  _instanceAProcess?.kill(ProcessSignal.sigkill);

  // Keep directories for inspection
  info('Keeping directories for inspection:');
  info('  Instance A: $instanceADataDir');
  info('  Instance B: $instanceBDataDir');
}

// ============================================================
// Test Functions
// ============================================================

Future<void> testSetup() async {
  section('Setup');

  // Check if build exists
  final executable = File('build/linux/x64/release/bundle/geogram_desktop');
  if (!await executable.exists()) {
    fail('Build check', 'Build not found at ${executable.path}');
    print('\nPlease run: flutter build linux --release\n');
    exit(1);
  }
  pass('Build exists');

  // Prepare directories
  await prepareDirectories();
  pass('Directories prepared');
}

Future<bool> testLaunchInstanceA() async {
  section('Launch Instance A');

  _instanceAProcess = await launchInstance(
    name: 'TestInstance-A',
    port: instanceAPort,
    dataDir: instanceADataDir,
    scanRange: scanLocalhostRange,
  );

  if (_instanceAProcess == null) {
    fail('Launch Instance A', 'Failed to start process');
    return false;
  }

  // Wait for startup
  await Future.delayed(startupWait);

  // Wait for ready
  if (!await waitForReady('Instance A', instanceAPort)) {
    fail('Instance A ready', 'Timeout waiting for API');
    return false;
  }

  // Get callsign
  _instanceACallsign = await getCallsign(instanceAPort);
  if (_instanceACallsign == null) {
    fail('Get Instance A callsign', 'Failed to extract callsign');
    return false;
  }

  pass('Instance A launched (callsign: $_instanceACallsign)');
  return true;
}

Future<bool> testLaunchInstanceB() async {
  section('Launch Instance B');

  _instanceBProcess = await launchInstance(
    name: 'TestInstance-B',
    port: instanceBPort,
    dataDir: instanceBDataDir,
    scanRange: scanLocalhostRange,
  );

  if (_instanceBProcess == null) {
    fail('Launch Instance B', 'Failed to start process');
    return false;
  }

  // Wait for startup
  await Future.delayed(startupWait);

  // Wait for ready
  if (!await waitForReady('Instance B', instanceBPort)) {
    fail('Instance B ready', 'Timeout waiting for API');
    return false;
  }

  // Get callsign
  _instanceBCallsign = await getCallsign(instanceBPort);
  if (_instanceBCallsign == null) {
    fail('Get Instance B callsign', 'Failed to extract callsign');
    return false;
  }

  pass('Instance B launched (callsign: $_instanceBCallsign)');
  return true;
}

Future<bool> testCreateBlog() async {
  section('Create Blog Post on Instance A');

  final result = await debugAction(instanceAPort, {
    'action': 'blog_create',
    'title': 'Shared App Data Test Post',
    'content':
        'This is a test blog post created to verify remote device browsing functionality works correctly.\n\nThe test verifies that Instance B can discover and browse this blog post from Instance A.',
    'status': 'published',
  });

  if (result?['success'] != true) {
    fail('Create blog post', result?['error'] ?? 'Unknown error');
    return false;
  }

  _createdBlogId = result?['blog_id'] as String?;
  if (_createdBlogId == null) {
    fail('Create blog post', 'No blog_id in response');
    return false;
  }

  info('Blog ID: $_createdBlogId');
  info('Blog file: ${result?['filename']}');
  pass('Blog post created');
  return true;
}

Future<bool> testDeviceDiscovery() async {
  section('Device Discovery');

  info('Waiting for Instance B to discover Instance A...');
  info('Timeout: ${discoveryTimeout.inSeconds}s');

  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < discoveryTimeout) {
    try {
      final response =
          await http.get(Uri.parse('http://localhost:$instanceBPort/api/devices'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final devices = data['devices'] as List? ?? [];

        // Check if Instance A is in the devices list
        final foundInstanceA = devices.any((device) {
          return device['callsign'] == _instanceACallsign;
        });

        if (foundInstanceA) {
          final elapsed = stopwatch.elapsed.inSeconds;
          pass('Instance B discovered Instance A in ${elapsed}s');
          return true;
        }
      }
    } catch (e) {
      // Keep trying
    }

    // Log progress every 5 seconds
    if (stopwatch.elapsed.inSeconds % 5 == 0 &&
        stopwatch.elapsed.inMilliseconds % 1000 < 500) {
      info('Still waiting... (${stopwatch.elapsed.inSeconds}s elapsed)');
    }

    await Future.delayed(const Duration(seconds: 1));
  }

  fail('Device discovery', 'Timeout after ${discoveryTimeout.inSeconds}s');
  return false;
}

Future<bool> testBrowseRemoteDeviceApps() async {
  section('Browse Remote Device Apps (Instance B browsing Instance A)');

  info('Instance B checking what apps are available on Instance A...');

  final result = await debugAction(instanceBPort, {
    'action': 'device_browse_apps',
    'callsign': _instanceACallsign,
  });

  if (result?['success'] != true) {
    fail('Browse remote apps', result?['error'] ?? 'Unknown error');
    info('Response: $result');
    return false;
  }

  final apps = result?['apps'] as List? ?? [];
  final appCount = result?['app_count'] as int? ?? 0;

  info('Found $appCount app(s) on Instance A: ${apps.map((a) => a['type']).toList()}');

  // Check if blog app is in the list
  final blogApp = apps.firstWhere(
    (app) => app['type'] == 'blog',
    orElse: () => <String, dynamic>{},
  );

  if (blogApp.isEmpty) {
    fail('Browse remote apps', 'Blog app not found in Instance A\'s public apps');
    info('Available apps: $apps');
    return false;
  }

  pass('Blog app discovered in Instance A\'s public data');

  // Verify blog has the post we created
  final itemCount = blogApp['itemCount'] as int? ?? 0;
  if (itemCount > 0) {
    pass('Blog has $itemCount post(s) visible from Instance B');
  } else {
    fail('Blog item count', 'Blog app found but shows 0 items (expected at least 1)');
    return false;
  }

  return true;
}

Future<void> _checkBlogCache() async {
  final cacheDir =
      Directory('$instanceBDataDir/devices/$_instanceACallsign/blog');

  if (await cacheDir.exists()) {
    int count = 0;
    await for (final entity in cacheDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        count++;
      }
    }

    if (count > 0) {
      pass('Instance B has cached blog data ($count posts)');
    } else {
      info('Cache directory exists but empty (expected - created on app open)');
    }
  } else {
    info('Cache not created yet (expected - created when browsing remote device)');
  }
}

Future<bool> testVerifyFileSystem() async {
  section('Verify File System Structure');

  final year = DateTime.now().year;
  final blogBasePath = '$instanceADataDir/devices/$_instanceACallsign/blog';
  final blogDir = Directory(blogBasePath);

  if (!await blogDir.exists()) {
    fail('Blog directory', 'Not found: $blogBasePath');
    return false;
  }
  pass('Blog directory exists');

  // Check year subdirectory
  final yearDir = Directory('$blogBasePath/$year');
  if (!await yearDir.exists()) {
    fail('Blog year directory', 'Not found: ${yearDir.path}');
    return false;
  }
  pass('Year directory exists: $year');

  // Find blog post directory
  bool foundBlogPost = false;
  await for (final entity in yearDir.list()) {
    if (entity is Directory && entity.path.contains(_createdBlogId!)) {
      // Check for post.md file
      final postFile = File('${entity.path}/post.md');
      if (await postFile.exists()) {
        foundBlogPost = true;
        pass('Blog post file found: ${entity.path}/post.md');

        // Read and verify content
        final content = await postFile.readAsString();
        if (content.contains('Shared App Data Test Post')) {
          pass('Blog post content verified');
        } else {
          warn('Blog post content may be incorrect');
        }
        break;
      }
    }
  }

  if (!foundBlogPost) {
    fail('Blog post file', 'Not found in year directory');
    return false;
  }

  return true;
}

// ============================================================
// Main Entry Point
// ============================================================

Future<void> main() async {
  print('\n\x1B[1m' + '=' * 60 + '\x1B[0m');
  print('\x1B[1mGeogram Shared App Data Test Suite\x1B[0m');
  print('\x1B[1m' + '=' * 60 + '\x1B[0m');

  try {
    // Run tests
    await testSetup();

    if (!await testLaunchInstanceA()) exit(1);
    if (!await testLaunchInstanceB()) exit(1);
    if (!await testCreateBlog()) exit(1);
    if (!await testDeviceDiscovery()) exit(1);
    if (!await testBrowseRemoteDeviceApps()) exit(1);
    if (!await testVerifyFileSystem()) exit(1);

    // Test results
    section('Test Results');
    print('\x1B[32mPassed: $_passed\x1B[0m');

    if (_failed > 0) {
      print('\x1B[31mFailed: $_failed\x1B[0m');
      print('\nFailures:');
      for (final failure in _failures) {
        print('  \x1B[31m- $failure\x1B[0m');
      }
      print('');
    } else {
      print('\n\x1B[1m\x1B[32m✓ All tests passed!\x1B[0m\n');
    }
  } finally {
    await cleanup();
  }

  exit(_failed > 0 ? 1 : 0);
}
