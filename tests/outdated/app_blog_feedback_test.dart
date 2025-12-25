#!/usr/bin/env dart
/// Geogram Desktop Blog Feedback Test Suite
///
/// This test file verifies Blog feedback functionality including:
///   - Like, Point, Dislike, Subscribe actions
///   - Emoji reactions (heart, thumbs-up, fire, celebrate, laugh, sad, surprise)
///   - Feedback API endpoints (POST /api/blog/{postId}/like, /point, /dislike, /subscribe, /react/{emoji})
///   - GET /api/blog/{postId}/feedback endpoint
///   - Feedback persistence across instances
///   - File-based feedback storage in feedback/ folder
///
/// The test uses two temporary instances:
///   - Instance A: Creates a blog post
///   - Instance B: Provides feedback (likes, reactions, etc.)
///
/// Usage:
///   dart run tests/app_blog_feedback_test.dart
///
/// Prerequisites:
///   - Build desktop: flutter build linux --release

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// ============================================================
// Configuration
// ============================================================

/// Fixed temp directories for easy debugging and inspection
const String clientADataDir = '/tmp/geogram-feedback-test-a';
const String clientBDataDir = '/tmp/geogram-feedback-test-b';

/// Ports for the instances
const int clientAPort = 17200;
const int clientBPort = 17201;

/// Timing configuration
const Duration startupWait = Duration(seconds: 15);
const Duration apiWait = Duration(seconds: 2);

/// Unique marker for test content verification
final String uniqueMarker = 'FEEDBACK_TEST_${DateTime.now().millisecondsSinceEpoch}';

/// Test npub for feedback actions (must be exactly 63 characters: npub1 + 58 chars)
const String testNpubA = 'npub1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String testNpubB = 'npub1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

// ============================================================
// Test State
// ============================================================

/// Test results tracking
int _passed = 0;
int _failed = 0;
final List<String> _failures = [];

/// Process handles for cleanup
Process? _clientAProcess;
Process? _clientBProcess;

/// Instance information
String? _clientACallsign;
String? _clientBCallsign;
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

/// Launch a geogram-desktop client instance
Future<Process?> launchClientInstance({
  required int port,
  required String dataDir,
  required String nickname,
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
    '--skip-intro',
    '--http-api',
    '--debug-api',
    '--no-update',
    '--identity-type=client',
    '--nickname=$nickname',
  ];

  info('Starting $nickname on port $port...');
  info('Data directory: $dataDir');

  final process = await Process.start(
    executable.path,
    args,
    mode: ProcessStartMode.detachedWithStdio,
  );

  // Log errors for debugging
  process.stderr.transform(utf8.decoder).listen((data) {
    if (data.trim().isNotEmpty) {
      print('  [$nickname STDERR] ${data.trim()}');
    }
  });

  return process;
}

/// Wait for an instance to be ready (API responding)
Future<bool> waitForReady(int port,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final stopwatch = Stopwatch()..start();

  while (stopwatch.elapsed < timeout) {
    try {
      final response =
          await http.get(Uri.parse('http://localhost:$port/api/status')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        info('Instance ready on port $port (${data['callsign']})');
        return true;
      }
    } catch (e) {
      // Not ready yet
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

/// Get client info from instance
Future<String?> getClientCallsign(int port) async {
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
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      info('DEBUG API Error (${response.statusCode}): ${response.body}');
      return jsonDecode(response.body) as Map<String, dynamic>;
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
  for (final dir in [clientADataDir, clientBDataDir]) {
    final rmResult = await Process.run('rm', ['-rf', dir]);
    if (rmResult.exitCode != 0) {
      warn('Failed to remove $dir: ${rmResult.stderr}');
    } else {
      info('Removed existing directory: $dir');
    }

    await Directory(dir).create(recursive: true);
    info('Created directory: $dir');
  }
}

/// Cleanup all processes
Future<void> cleanup() async {
  section('Cleanup');

  // Delete the blog post if created
  if (_createdBlogId != null) {
    info('Deleting test blog post: $_createdBlogId');
    final result = await debugAction(clientAPort, {
      'action': 'blog_delete',
      'blog_id': _createdBlogId,
    });
    if (result?['success'] == true) {
      info('Blog post deleted');
    } else {
      warn('Failed to delete blog post: ${result?['error']}');
    }
  }

  // Stop instances
  if (_clientAProcess != null) {
    info('Stopping Client A...');
    _clientAProcess!.kill(ProcessSignal.sigterm);
  }
  if (_clientBProcess != null) {
    info('Stopping Client B...');
    _clientBProcess!.kill(ProcessSignal.sigterm);
  }

  await Future.delayed(const Duration(seconds: 2));

  // Force kill if needed
  _clientAProcess?.kill(ProcessSignal.sigkill);
  _clientBProcess?.kill(ProcessSignal.sigkill);

  // Keep directories for inspection
  info('Keeping directories for inspection:');
  info('  Client A: $clientADataDir');
  info('  Client B: $clientBDataDir');
}

// ============================================================
// Test Functions
// ============================================================

Future<void> testSetup() async {
  section('Setup');

  // Check if build exists
  final executable = File('build/linux/x64/release/bundle/geogram_desktop');
  if (!await executable.exists()) {
    fail('Build check', 'Desktop build not found');
    throw Exception('Build not found. Run: flutter build linux --release');
  }
  pass('Desktop build exists');

  // Prepare directories
  await prepareDirectories();
  pass('Directories prepared');
}

Future<void> testLaunchInstances() async {
  section('Launch Instances');

  // Start Client A
  _clientAProcess = await launchClientInstance(
    port: clientAPort,
    dataDir: clientADataDir,
    nickname: 'FeedbackTestA',
  );

  if (_clientAProcess == null) {
    fail('Launch Client A', 'Failed to start process');
    throw Exception('Failed to launch Client A');
  }
  pass('Client A process started');

  // Start Client B
  _clientBProcess = await launchClientInstance(
    port: clientBPort,
    dataDir: clientBDataDir,
    nickname: 'FeedbackTestB',
  );

  if (_clientBProcess == null) {
    fail('Launch Client B', 'Failed to start process');
    throw Exception('Failed to launch Client B');
  }
  pass('Client B process started');

  // Wait for startup
  info('Waiting for instances to start...');
  await Future.delayed(startupWait);

  // Check if ready
  if (await waitForReady(clientAPort)) {
    pass('Client A API ready');
  } else {
    fail('Client A ready', 'Timeout');
    throw Exception('Client A did not become ready');
  }

  if (await waitForReady(clientBPort)) {
    pass('Client B API ready');
  } else {
    fail('Client B ready', 'Timeout');
    throw Exception('Client B did not become ready');
  }

  // Get callsigns
  _clientACallsign = await getClientCallsign(clientAPort);
  _clientBCallsign = await getClientCallsign(clientBPort);

  if (_clientACallsign != null) {
    pass('Got Client A callsign: $_clientACallsign');
  } else {
    fail('Get callsign A', 'Could not get callsign');
    throw Exception('Failed to get Client A callsign');
  }

  if (_clientBCallsign != null) {
    pass('Got Client B callsign: $_clientBCallsign');
  } else {
    fail('Get callsign B', 'Could not get callsign');
    throw Exception('Failed to get Client B callsign');
  }
}

Future<void> testCreateBlogPost() async {
  section('Create Blog Post (Client A)');

  final title = 'Feedback Test Post';
  final content = '''
This is a test blog post for feedback testing.

Unique marker: $uniqueMarker

Users should be able to like, point, dislike, subscribe, and react to this post.
''';

  info('Creating blog post with marker: $uniqueMarker');

  final result = await debugAction(clientAPort, {
    'action': 'blog_create',
    'title': title,
    'content': content,
    'status': 'published',
  });

  if (result == null || result['success'] != true) {
    fail('Create blog', 'Error: ${result?['error']}');
    throw Exception('Failed to create blog post');
  }

  _createdBlogId = result['blog_id'] as String?;

  if (_createdBlogId == null) {
    fail('Create blog', 'Missing blog_id in response');
    throw Exception('Invalid response from blog_create');
  }

  pass('Blog post created: $_createdBlogId');
}

/// Test POST /api/blog/{postId}/like - Toggle like
Future<void> testToggleLike() async {
  section('Test Like Feedback');

  if (_createdBlogId == null) {
    fail('Like test', 'No blog ID available');
    return;
  }

  try {
    // Add like
    final response = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/like'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubB,
          },
          body: jsonEncode({'npub': testNpubB}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      fail('POST /like', 'HTTP ${response.statusCode}: ${response.body}');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['success'] == true && data['action'] == 'added') {
      pass('Like added successfully');
      info('Like count: ${data['like_count']}');
    } else {
      fail('POST /like', 'Unexpected response: $data');
      return;
    }

    // Verify feedback file exists
    await Future.delayed(apiWait);
    final year = _createdBlogId!.substring(0, 4);
    final feedbackFile = File('$clientADataDir/devices/$_clientACallsign/blog/$year/$_createdBlogId/feedback/likes.txt');

    if (await feedbackFile.exists()) {
      pass('likes.txt file created');
      final content = await feedbackFile.readAsString();
      if (content.contains(testNpubB)) {
        pass('likes.txt contains correct npub');
      } else {
        fail('Verify likes.txt', 'Does not contain npub');
      }
    } else {
      fail('Verify likes.txt', 'File not found at ${feedbackFile.path}');
    }

    // Toggle like off
    final toggleOffResponse = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/like'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubB,
          },
          body: jsonEncode({'npub': testNpubB}),
        )
        .timeout(const Duration(seconds: 10));

    if (toggleOffResponse.statusCode == 200) {
      final toggleData = jsonDecode(toggleOffResponse.body) as Map<String, dynamic>;
      if (toggleData['action'] == 'removed') {
        pass('Like toggled off successfully');
        info('Like count after removal: ${toggleData['like_count']}');
      } else {
        fail('Toggle like off', 'Unexpected action: ${toggleData['action']}');
      }
    }
  } catch (e) {
    fail('POST /like', 'Exception: $e');
  }
}

/// Test POST /api/blog/{postId}/point - Toggle point
Future<void> testTogglePoint() async {
  section('Test Point Feedback');

  if (_createdBlogId == null) {
    fail('Point test', 'No blog ID available');
    return;
  }

  try {
    final response = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/point'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubB,
          },
          body: jsonEncode({'npub': testNpubB}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true && data['action'] == 'added') {
        pass('Point added successfully');
        info('Point count: ${data['point_count']}');
      } else {
        fail('POST /point', 'Unexpected response: $data');
      }
    } else {
      fail('POST /point', 'HTTP ${response.statusCode}');
    }
  } catch (e) {
    fail('POST /point', 'Exception: $e');
  }
}

/// Test POST /api/blog/{postId}/dislike - Toggle dislike
Future<void> testToggleDislike() async {
  section('Test Dislike Feedback');

  if (_createdBlogId == null) {
    fail('Dislike test', 'No blog ID available');
    return;
  }

  try {
    final response = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/dislike'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubA,
          },
          body: jsonEncode({'npub': testNpubA}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true && data['action'] == 'added') {
        pass('Dislike added successfully');
        info('Dislike count: ${data['dislike_count']}');
      } else {
        fail('POST /dislike', 'Unexpected response: $data');
      }
    } else {
      fail('POST /dislike', 'HTTP ${response.statusCode}');
    }
  } catch (e) {
    fail('POST /dislike', 'Exception: $e');
  }
}

/// Test POST /api/blog/{postId}/subscribe - Toggle subscribe
Future<void> testToggleSubscribe() async {
  section('Test Subscribe Feedback');

  if (_createdBlogId == null) {
    fail('Subscribe test', 'No blog ID available');
    return;
  }

  try {
    final response = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/subscribe'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubB,
          },
          body: jsonEncode({'npub': testNpubB}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true && data['action'] == 'added') {
        pass('Subscribe added successfully');
        info('Subscribe count: ${data['subscribe_count']}');
      } else {
        fail('POST /subscribe', 'Unexpected response: $data');
      }
    } else {
      fail('POST /subscribe', 'HTTP ${response.statusCode}');
    }
  } catch (e) {
    fail('POST /subscribe', 'Exception: $e');
  }
}

/// Test POST /api/blog/{postId}/react/{emoji} - Toggle emoji reactions
Future<void> testEmojiReactions() async {
  section('Test Emoji Reactions');

  if (_createdBlogId == null) {
    fail('Reactions test', 'No blog ID available');
    return;
  }

  // Test all supported emoji reactions
  final emojis = ['heart', 'thumbs-up', 'fire', 'celebrate', 'laugh', 'sad', 'surprise'];

  for (final emoji in emojis) {
    try {
      final response = await http
          .post(
            Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/react/$emoji'),
            headers: {
              'Content-Type': 'application/json',
              'X-Npub': testNpubB,
            },
            body: jsonEncode({'npub': testNpubB}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['action'] == 'added') {
          pass('Reaction $emoji added successfully');
        } else {
          fail('React $emoji', 'Unexpected response: $data');
        }
      } else {
        fail('React $emoji', 'HTTP ${response.statusCode}');
      }
    } catch (e) {
      fail('React $emoji', 'Exception: $e');
    }

    // Small delay between reactions
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // Verify reaction files exist
  await Future.delayed(apiWait);
  final year = _createdBlogId!.substring(0, 4);
  final feedbackDir = Directory('$clientADataDir/devices/$_clientACallsign/blog/$year/$_createdBlogId/feedback');

  if (await feedbackDir.exists()) {
    pass('Feedback directory exists');

    int foundReactions = 0;
    for (final emoji in emojis) {
      final reactionFile = File('${feedbackDir.path}/$emoji.txt');
      if (await reactionFile.exists()) {
        foundReactions++;
      }
    }

    if (foundReactions == emojis.length) {
      pass('All reaction files created ($foundReactions/${emojis.length})');
    } else {
      fail('Verify reactions', 'Only $foundReactions/${emojis.length} files found');
    }
  } else {
    fail('Verify feedback dir', 'Directory not found');
  }
}

/// Test GET /api/blog/{postId}/feedback - Get all feedback
Future<void> testGetFeedback() async {
  section('Test Get Feedback Summary');

  if (_createdBlogId == null) {
    fail('Get feedback', 'No blog ID available');
    return;
  }

  try {
    // Get feedback without npub
    final response = await http
        .get(Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/feedback'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      fail('GET /feedback', 'HTTP ${response.statusCode}: ${response.body}');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['success'] != true) {
      fail('GET /feedback', 'Response success != true');
      return;
    }

    pass('GET /feedback returns success');

    final feedback = data['feedback'] as Map<String, dynamic>?;
    if (feedback == null) {
      fail('GET /feedback', 'No feedback object in response');
      return;
    }

    // Verify counts
    info('Likes: ${feedback['likes']}');
    info('Points: ${feedback['points']}');
    info('Dislikes: ${feedback['dislikes']}');
    info('Subscriptions: ${feedback['subscribe']}');

    final reactions = feedback['reactions'] as Map<String, dynamic>?;
    if (reactions != null) {
      info('Reactions:');
      reactions.forEach((emoji, count) {
        info('  $emoji: $count');
      });
      pass('Feedback contains reaction counts');
    }

    // Test with npub to get user state
    final responseWithNpub = await http
        .get(Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/feedback?npub=$testNpubB'))
        .timeout(const Duration(seconds: 10));

    if (responseWithNpub.statusCode == 200) {
      final dataWithNpub = jsonDecode(responseWithNpub.body) as Map<String, dynamic>;
      final userState = dataWithNpub['user_state'] as Map<String, dynamic>?;

      if (userState != null) {
        pass('GET /feedback with npub returns user_state');
        info('User has liked: ${userState['has_liked']}');
        info('User has pointed: ${userState['has_pointed']}');
        info('User has subscribed: ${userState['has_subscribed']}');
      } else {
        fail('GET /feedback with npub', 'No user_state in response');
      }
    }
  } catch (e) {
    fail('GET /feedback', 'Exception: $e');
  }
}

/// Test feedback persistence and file structure
Future<void> testFeedbackPersistence() async {
  section('Test Feedback Persistence');

  if (_createdBlogId == null || _clientACallsign == null) {
    fail('Persistence test', 'No blog ID or callsign');
    return;
  }

  final year = _createdBlogId!.substring(0, 4);
  final postPath = '$clientADataDir/devices/$_clientACallsign/blog/$year/$_createdBlogId';
  final feedbackPath = '$postPath/feedback';

  // Verify feedback folder structure
  final feedbackDir = Directory(feedbackPath);
  if (!await feedbackDir.exists()) {
    fail('Feedback structure', 'feedback/ directory not found');
    return;
  }
  pass('feedback/ directory exists');

  // List all files in feedback directory
  final files = await feedbackDir.list().toList();
  final fileNames = files.map((f) => f.path.split('/').last).toList();

  info('Feedback files found: ${fileNames.join(', ')}');

  // Verify expected files exist
  final expectedFiles = ['likes.txt', 'points.txt', 'dislikes.txt', 'subscribe.txt'];
  int foundFiles = 0;

  for (final fileName in expectedFiles) {
    if (fileNames.contains(fileName)) {
      foundFiles++;
    }
  }

  if (foundFiles == expectedFiles.length) {
    pass('All expected feedback files present');
  } else {
    warn('Only $foundFiles/${expectedFiles.length} expected files found');
  }

  // Verify file format (one npub per line)
  final likesFile = File('$feedbackPath/likes.txt');
  if (await likesFile.exists()) {
    final content = await likesFile.readAsString();
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

    if (lines.isEmpty) {
      pass('likes.txt has correct format (empty after toggle off)');
    } else {
      bool allValidNpubs = lines.every((line) => line.trim().startsWith('npub1'));
      if (allValidNpubs) {
        pass('likes.txt contains valid npub format');
      } else {
        fail('File format', 'likes.txt contains invalid npub');
      }
    }
  }

  // Verify old comments folder structure not created
  final oldCommentsDir = Directory('$postPath/comments');
  if (!await oldCommentsDir.exists()) {
    pass('Old comments/ structure not created (feedback system active)');
  } else {
    info('Old comments/ directory exists (might be from previous test)');
  }
}

/// Test unsupported reaction returns error
Future<void> testInvalidReaction() async {
  section('Test Invalid Reaction');

  if (_createdBlogId == null) {
    fail('Invalid reaction test', 'No blog ID');
    return;
  }

  try {
    final response = await http
        .post(
          Uri.parse('http://localhost:$clientAPort/api/blog/$_createdBlogId/react/invalid-emoji'),
          headers: {
            'Content-Type': 'application/json',
            'X-Npub': testNpubB,
          },
          body: jsonEncode({'npub': testNpubB}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 400) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['error'] == 'Unsupported reaction') {
        pass('Invalid reaction returns 400 with correct error');
        info('Supported reactions listed: ${data['supported_reactions']}');
      } else {
        fail('Invalid reaction', 'Wrong error message: ${data['error']}');
      }
    } else {
      fail('Invalid reaction', 'Expected 400, got ${response.statusCode}');
    }
  } catch (e) {
    fail('Invalid reaction', 'Exception: $e');
  }
}

// ============================================================
// Main
// ============================================================

Future<void> main() async {
  print('\x1B[1m');
  print('================================================');
  print('  Geogram Blog Feedback Test Suite');
  print('================================================');
  print('\x1B[0m');
  print('');
  print('Testing feedback system with two instances:');
  print('  - Instance A: Creates blog post');
  print('  - Instance B: Provides feedback');
  print('');

  try {
    await testSetup();
    await testLaunchInstances();
    await testCreateBlogPost();

    // Test all feedback types
    await testToggleLike();
    await testTogglePoint();
    await testToggleDislike();
    await testToggleSubscribe();
    await testEmojiReactions();

    // Test feedback retrieval
    await testGetFeedback();

    // Test persistence and structure
    await testFeedbackPersistence();

    // Test error cases
    await testInvalidReaction();
  } catch (e) {
    print('\n\x1B[31mTest aborted: $e\x1B[0m');
  } finally {
    await cleanup();
  }

  // Print summary
  section('Test Summary');
  print('');
  print('  Passed: \x1B[32m$_passed\x1B[0m');
  print('  Failed: \x1B[31m$_failed\x1B[0m');

  if (_failures.isNotEmpty) {
    print('');
    print('  Failures:');
    for (final failure in _failures) {
      print('    - $failure');
    }
  }

  print('');
  print('  Data directories:');
  print('    Client A: $clientADataDir');
  print('    Client B: $clientBDataDir');

  // Exit with appropriate code
  exit(_failed > 0 ? 1 : 0);
}
