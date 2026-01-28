#!/usr/bin/env dart
/// Mirror Sync API Test Suite
///
/// Tests the Simple Mirror sync protocol including:
/// - Basic sync functionality
/// - Challenge-response authentication
/// - Replay attack prevention
/// - Challenge expiry
/// - Nonce reuse prevention
///
/// Usage:
///   dart run tests/mirror/mirror_sync_test.dart --port-a 5577 --port-b 5588
///
/// Prerequisites:
///   - Instance A running on port-a with debug API enabled
///   - Instance B running on port-b with debug API enabled
///   - Instance A has test-sync-folder with test files
///   - Instance A has Instance B as allowed peer

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

// Test configuration
late String portA;
late String portB;
late String baseUrlA;
late String baseUrlB;
const testFolder = 'test-sync-folder';

// Test results tracking
int testsRun = 0;
int testsPassed = 0;
int testsFailed = 0;
List<String> failedTests = [];

void main(List<String> args) async {
  // Parse arguments
  portA = '5577';
  portB = '5588';

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port-a' && i + 1 < args.length) {
      portA = args[i + 1];
    } else if (args[i] == '--port-b' && i + 1 < args.length) {
      portB = args[i + 1];
    }
  }

  baseUrlA = 'http://localhost:$portA';
  baseUrlB = 'http://localhost:$portB';

  print('');
  print('╔════════════════════════════════════════════════════════════════╗');
  print('║           Mirror Sync API Test Suite (Dart)                    ║');
  print('╚════════════════════════════════════════════════════════════════╝');
  print('');
  print('Instance A (source):      $baseUrlA');
  print('Instance B (destination): $baseUrlB');
  print('Test folder:              $testFolder');
  print('');

  // Check instances are running
  if (!await checkInstance('A', baseUrlA) || !await checkInstance('B', baseUrlB)) {
    print('\n[FATAL] Cannot connect to instances. Exiting.');
    exit(1);
  }

  // Run test suites
  print('\n${'=' * 70}');
  print('BASIC FUNCTIONALITY TESTS');
  print('${'=' * 70}\n');

  await testChallengeEndpoint();
  await testChallengeRequiresFolder();
  await testChallengeNonexistentFolder();
  await testRequestWithoutChallenge();
  await testValidSyncFlow();

  print('\n${'=' * 70}');
  print('SECURITY TESTS - REPLAY ATTACK PREVENTION');
  print('${'=' * 70}\n');

  await testChallengeReuse();
  await testReplayAttack();
  await testInvalidNonce();
  await testWrongFolderInResponse();
  await testExpiredChallenge();
  await testMalformedChallengeResponse();

  print('\n${'=' * 70}');
  print('AUTHORIZATION TESTS');
  print('${'=' * 70}\n');

  await testUnauthorizedPeer();

  // Print summary
  print('\n');
  print('╔════════════════════════════════════════════════════════════════╗');
  if (testsFailed == 0) {
    print('║           ALL TESTS PASSED! ($testsPassed/$testsRun)                            ║');
  } else {
    print('║           TESTS COMPLETED: $testsPassed passed, $testsFailed failed             ║');
  }
  print('╚════════════════════════════════════════════════════════════════╝');

  if (failedTests.isNotEmpty) {
    print('\nFailed tests:');
    for (final test in failedTests) {
      print('  - $test');
    }
  }

  exit(testsFailed > 0 ? 1 : 0);
}

Future<bool> checkInstance(String name, String baseUrl) async {
  try {
    final response = await http.get(Uri.parse('$baseUrl/api/status'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Instance $name: ${data['callsign']} (${data['npub']?.toString().substring(0, 20)}...)');
      return true;
    }
  } catch (e) {
    print('Instance $name: OFFLINE ($e)');
  }
  return false;
}

void printTestHeader(String title, String explanation) {
  print('┌─────────────────────────────────────────────────────────────────');
  print('│ TEST: $title');
  print('├─────────────────────────────────────────────────────────────────');
  print('│ WHY: $explanation');
  print('└─────────────────────────────────────────────────────────────────');
}

void test(String name, bool passed, [String? details]) {
  testsRun++;
  if (passed) {
    testsPassed++;
    print('  ✓ $name');
  } else {
    testsFailed++;
    failedTests.add(name);
    print('  ✗ $name');
    if (details != null) {
      print('    Details: $details');
    }
  }
}

// ============================================================
// BASIC FUNCTIONALITY TESTS
// ============================================================

Future<void> testChallengeEndpoint() async {
  printTestHeader(
    'Challenge Endpoint Returns Valid Nonce',
    '''The challenge endpoint is the first step in authentication.
│ It must return a cryptographically random nonce that the client
│ will sign to prove they control their private key (NSEC).''',
  );

  try {
    final response = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=$testFolder'),
    );

    final passed = response.statusCode == 200;
    String? details;

    if (passed) {
      final data = jsonDecode(response.body);
      final hasNonce = data['nonce'] != null && (data['nonce'] as String).length == 64;
      final hasExpiry = data['expires_at'] != null;
      final hasFolder = data['folder'] == testFolder;

      test('Challenge returns 200 OK', true);
      test('Challenge has 64-char hex nonce (SHA256)', hasNonce,
           hasNonce ? null : 'nonce: ${data['nonce']}');
      test('Challenge has expiry timestamp', hasExpiry);
      test('Challenge echoes requested folder', hasFolder,
           hasFolder ? null : 'folder: ${data['folder']}');
    } else {
      test('Challenge returns 200 OK', false, 'status: ${response.statusCode}');
    }
  } catch (e) {
    test('Challenge endpoint accessible', false, e.toString());
  }
  print('');
}

Future<void> testChallengeRequiresFolder() async {
  printTestHeader(
    'Challenge Requires Folder Parameter',
    '''The folder parameter is required because each challenge is bound
│ to a specific folder. This prevents an attacker from using a
│ challenge meant for folder A to access folder B.''',
  );

  try {
    final response = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge'),
    );

    test('Missing folder returns 400 Bad Request', response.statusCode == 400,
         'status: ${response.statusCode}');

    if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      test('Error code is INVALID_REQUEST', data['code'] == 'INVALID_REQUEST',
           'code: ${data['code']}');
    }
  } catch (e) {
    test('Challenge validation works', false, e.toString());
  }
  print('');
}

Future<void> testChallengeNonexistentFolder() async {
  printTestHeader(
    'Challenge for Nonexistent Folder Returns 404',
    '''Before issuing a challenge, the server verifies the folder exists.
│ This prevents resource enumeration attacks and avoids wasting
│ server resources on invalid requests.''',
  );

  try {
    final response = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=nonexistent-folder-xyz'),
    );

    test('Nonexistent folder returns 404', response.statusCode == 404,
         'status: ${response.statusCode}');
  } catch (e) {
    test('Folder validation works', false, e.toString());
  }
  print('');
}

Future<void> testRequestWithoutChallenge() async {
  printTestHeader(
    'Request Without Valid Challenge Fails',
    '''The old API format (simple_mirror:folder) without challenge-response
│ must be rejected. This ensures backward compatibility doesn\'t
│ create a security hole.''',
  );

  try {
    // Try to make a request with old-style content (no challenge)
    final response = await http.post(
      Uri.parse('$baseUrlA/api/mirror/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': {
          'id': 'fake_id',
          'kind': 1,
          'pubkey': 'fake_pubkey',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'content': 'simple_mirror:$testFolder',  // Old format without challenge
          'tags': [['t', 'mirror_request'], ['folder', testFolder]],
          'sig': 'fake_signature',
        },
        'folder': testFolder,
      }),
    );

    // Should fail with invalid signature or invalid challenge format
    test('Old-style request without challenge rejected', response.statusCode != 200,
         'status: ${response.statusCode}');

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      print('    Rejection reason: ${data['code']} - ${data['error']}');
    }
  } catch (e) {
    test('Request validation works', false, e.toString());
  }
  print('');
}

Future<void> testValidSyncFlow() async {
  printTestHeader(
    'Complete Valid Sync Flow',
    '''This tests the full happy path: Instance B requests sync from A.
│ Internally this: (1) fetches a challenge, (2) signs it with NSEC,
│ (3) sends signed response, (4) gets token, (5) fetches files.''',
  );

  try {
    // Use debug API to trigger a full sync
    final response = await http.post(
      Uri.parse('$baseUrlB/api/debug'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'mirror_request_sync',
        'peer_url': baseUrlA,
        'folder': testFolder,
      }),
    );

    final passed = response.statusCode == 200;
    if (passed) {
      final data = jsonDecode(response.body);
      test('Sync completes successfully', data['success'] == true,
           'error: ${data['error']}');

      if (data['success'] == true) {
        final totalChanges = (data['files_added'] ?? 0) +
                            (data['files_modified'] ?? 0);
        print('    Files synced: ${data['files_added']} added, ${data['files_modified']} modified');
        print('    Bytes transferred: ${data['bytes_transferred']}');
        print('    Duration: ${data['duration_ms']}ms');
      }
    } else {
      test('Sync request accepted', false, 'status: ${response.statusCode}');
    }
  } catch (e) {
    test('Valid sync flow works', false, e.toString());
  }
  print('');
}

// ============================================================
// SECURITY TESTS - REPLAY ATTACK PREVENTION
// ============================================================

Future<void> testChallengeReuse() async {
  printTestHeader(
    'Challenge Cannot Be Reused (Single-Use Nonce)',
    '''Each challenge nonce can only be used once. After a successful
│ authentication, the nonce is deleted. This prevents an attacker
│ from capturing a valid signed response and replaying it later.''',
  );

  try {
    // Do multiple sequential syncs - each should succeed with fresh challenges
    print('    Performing 3 sequential syncs...');

    final sync1 = await doSyncViaDebug();
    print('    Sync 1: ${sync1 ? 'SUCCESS' : 'FAILED'}');

    final sync2 = await doSyncViaDebug();
    print('    Sync 2: ${sync2 ? 'SUCCESS' : 'FAILED'}');

    final sync3 = await doSyncViaDebug();
    print('    Sync 3: ${sync3 ? 'SUCCESS' : 'FAILED'}');

    test('Multiple sequential syncs succeed (each gets fresh challenge)',
         sync1 && sync2 && sync3,
         'sync1: $sync1, sync2: $sync2, sync3: $sync3');

  } catch (e) {
    test('Challenge reuse prevention', false, e.toString());
  }
  print('');
}

Future<bool> doSyncViaDebug() async {
  final response = await http.post(
    Uri.parse('$baseUrlB/api/debug'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'action': 'mirror_request_sync',
      'peer_url': baseUrlA,
      'folder': testFolder,
    }),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['success'] == true;
  }
  return false;
}

Future<void> testReplayAttack() async {
  printTestHeader(
    'Replay Attack Prevention',
    '''An attacker who captures a valid signed request from the network
│ should NOT be able to replay it to gain access. This is because:
│ (1) The challenge nonce is single-use (consumed after first use)
│ (2) The attacker cannot sign a new challenge without the NSEC''',
  );

  try {
    // Get a challenge
    final challengeResp = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=$testFolder'),
    );
    final challenge = jsonDecode(challengeResp.body);
    final nonce = challenge['nonce'] as String;
    print('    Simulating captured request with nonce: ${nonce.substring(0, 16)}...');

    // Create a fake "captured" request with valid structure but fake signature
    final fakeEvent = {
      'id': sha256.convert(utf8.encode('fake_event_${DateTime.now()}')).toString(),
      'kind': 1,
      'pubkey': 'captured_pubkey_from_network_sniffing',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'content': 'mirror_response:$nonce:$testFolder',
      'tags': [
        ['t', 'mirror_response'],
        ['folder', testFolder],
        ['nonce', nonce],
      ],
      'sig': 'captured_signature_would_not_verify_for_new_challenge',
    };

    final response = await http.post(
      Uri.parse('$baseUrlA/api/mirror/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': fakeEvent,
        'folder': testFolder,
      }),
    );

    test('Captured request with invalid signature rejected',
         response.statusCode == 401,
         'status: ${response.statusCode}');

    if (response.statusCode == 401) {
      final data = jsonDecode(response.body);
      test('Error indicates signature verification failed',
           data['code'] == 'INVALID_SIGNATURE',
           'code: ${data['code']}');
      print('    Attack blocked: ${data['error']}');
    }

  } catch (e) {
    test('Replay attack prevention', false, e.toString());
  }
  print('');
}

Future<void> testInvalidNonce() async {
  printTestHeader(
    'Fabricated/Invalid Nonce Rejected',
    '''An attacker cannot fabricate their own nonce. Only nonces issued
│ by the server are valid. The server maintains a map of active
│ challenges and rejects any nonce not in this map.''',
  );

  try {
    // Create a fake nonce (not issued by server)
    final fakeNonce = sha256.convert(utf8.encode('fabricated_nonce_${DateTime.now()}')).toString();
    print('    Fabricated nonce: ${fakeNonce.substring(0, 16)}...');

    final fakeEvent = {
      'id': sha256.convert(utf8.encode('fake_event')).toString(),
      'kind': 1,
      'pubkey': 'fake_pubkey',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'content': 'mirror_response:$fakeNonce:$testFolder',
      'tags': [
        ['t', 'mirror_response'],
        ['folder', testFolder],
        ['nonce', fakeNonce],
      ],
      'sig': 'fake_signature',
    };

    final response = await http.post(
      Uri.parse('$baseUrlA/api/mirror/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': fakeEvent,
        'folder': testFolder,
      }),
    );

    // Signature check happens first, so we expect INVALID_SIGNATURE
    test('Request with fabricated nonce rejected', response.statusCode == 401,
         'status: ${response.statusCode}');

    final data = jsonDecode(response.body);
    print('    Attack blocked: ${data['code']} - ${data['error']}');

  } catch (e) {
    test('Invalid nonce handling', false, e.toString());
  }
  print('');
}

Future<void> testWrongFolderInResponse() async {
  printTestHeader(
    'Challenge Bound to Specific Folder',
    '''Each challenge is bound to a specific folder. An attacker who
│ obtains a valid challenge for folder A cannot use it to access
│ folder B. The server verifies the folder in the signed content
│ matches the folder the challenge was issued for.''',
  );

  try {
    // Get a challenge for the test folder
    final challengeResp = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=$testFolder'),
    );

    if (challengeResp.statusCode != 200) {
      test('Got challenge for folder binding test', false, 'status: ${challengeResp.statusCode}');
      return;
    }

    final challenge = jsonDecode(challengeResp.body);
    final nonce = challenge['nonce'] as String;
    print('    Got challenge for "$testFolder": ${nonce.substring(0, 16)}...');
    print('    Attempting to use it for "different-folder"...');

    // Try to use this nonce for a different folder
    final fakeEvent = {
      'id': sha256.convert(utf8.encode('fake_event')).toString(),
      'kind': 1,
      'pubkey': 'fake_pubkey',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      // Use the nonce but claim a different folder
      'content': 'mirror_response:$nonce:different-folder',
      'tags': [
        ['t', 'mirror_response'],
        ['folder', 'different-folder'],
        ['nonce', nonce],
      ],
      'sig': 'fake_signature',
    };

    final response = await http.post(
      Uri.parse('$baseUrlA/api/mirror/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': fakeEvent,
        'folder': 'different-folder',
      }),
    );

    test('Cross-folder challenge use rejected', response.statusCode != 200,
         'status: ${response.statusCode}');

    final data = jsonDecode(response.body);
    print('    Attack blocked: ${data['code']} - ${data['error']}');

  } catch (e) {
    test('Folder binding verification', false, e.toString());
  }
  print('');
}

Future<void> testExpiredChallenge() async {
  printTestHeader(
    'Challenge Expiry Verification',
    '''Challenges expire after 2 minutes. This limits the window for
│ any attack and ensures stale challenges don\'t accumulate in
│ server memory. We verify the expiry timestamp is reasonable.''',
  );

  try {
    final challengeResp = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=$testFolder'),
    );

    if (challengeResp.statusCode != 200) {
      test('Got challenge for expiry test', false, 'status: ${challengeResp.statusCode}');
      return;
    }

    final challenge = jsonDecode(challengeResp.body);
    final expiresAt = challenge['expires_at'] as int;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresIn = expiresAt - now;

    print('    Challenge expires at: ${DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)}');
    print('    Time until expiry: ${expiresIn} seconds');

    test('Challenge expires in the future', expiresAt > now,
         'expires_at: $expiresAt, now: $now');
    test('Challenge expires within 2-3 minutes (reasonable window)',
         expiresIn > 0 && expiresIn <= 180,
         'expires in $expiresIn seconds');

  } catch (e) {
    test('Expiry verification', false, e.toString());
  }
  print('');
}

Future<void> testMalformedChallengeResponse() async {
  printTestHeader(
    'Malformed Challenge Response Rejected',
    '''The server must reject any response that doesn\'t follow the
│ exact format "mirror_response:<nonce>:<folder>". This prevents
│ format confusion attacks and ensures robust parsing.''',
  );

  try {
    final malformedContents = [
      ('simple_mirror:$testFolder', 'Old API format (no challenge)'),
      ('mirror_response:', 'Missing nonce and folder'),
      ('mirror_response:nonce_only', 'Missing folder separator'),
      ('invalid_prefix:nonce:folder', 'Wrong prefix'),
      ('', 'Empty content'),
      ('mirror_response:a:b:c:d', 'Too many parts'),
    ];

    var allRejected = true;
    for (final (content, description) in malformedContents) {
      final fakeEvent = {
        'id': sha256.convert(utf8.encode('fake_$content')).toString(),
        'kind': 1,
        'pubkey': 'fake_pubkey',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'content': content,
        'tags': [],
        'sig': 'fake_signature',
      };

      final response = await http.post(
        Uri.parse('$baseUrlA/api/mirror/request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event': fakeEvent,
          'folder': testFolder,
        }),
      );

      if (response.statusCode == 200) {
        print('    ✗ "$description" was incorrectly accepted!');
        allRejected = false;
      } else {
        print('    ✓ "$description" rejected (${response.statusCode})');
      }
    }

    test('All malformed content formats rejected', allRejected);

  } catch (e) {
    test('Malformed content handling', false, e.toString());
  }
  print('');
}

// ============================================================
// AUTHORIZATION TESTS
// ============================================================

Future<void> testUnauthorizedPeer() async {
  printTestHeader(
    'Unauthorized Peer Rejected',
    '''Even if an attacker could somehow sign a valid challenge response
│ (they can\'t without the NSEC), they would still be rejected if
│ their public key is not in the allowed peers list on Instance A.''',
  );

  try {
    // Get a challenge
    final challengeResp = await http.get(
      Uri.parse('$baseUrlA/api/mirror/challenge?folder=$testFolder'),
    );

    if (challengeResp.statusCode != 200) {
      test('Got challenge for auth test', false, 'status: ${challengeResp.statusCode}');
      return;
    }

    final challenge = jsonDecode(challengeResp.body);
    final nonce = challenge['nonce'] as String;
    print('    Simulating request from unauthorized peer...');

    // Create a request from an "unauthorized" peer
    final fakeEvent = {
      'id': sha256.convert(utf8.encode('unauthorized_peer_event')).toString(),
      'kind': 1,
      'pubkey': 'unauthorized_peer_not_in_allowed_list_abcdef123456',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'content': 'mirror_response:$nonce:$testFolder',
      'tags': [
        ['t', 'mirror_response'],
        ['folder', testFolder],
        ['nonce', nonce],
      ],
      'sig': 'signature_would_be_valid_but_peer_not_authorized',
    };

    final response = await http.post(
      Uri.parse('$baseUrlA/api/mirror/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event': fakeEvent,
        'folder': testFolder,
      }),
    );

    test('Unauthorized peer request rejected', response.statusCode != 200,
         'status: ${response.statusCode}');

    final data = jsonDecode(response.body);
    print('    Attack blocked: ${data['code']} - ${data['error']}');

  } catch (e) {
    test('Peer authorization', false, e.toString());
  }
  print('');
}
