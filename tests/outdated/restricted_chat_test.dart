#!/usr/bin/env dart
/// Restricted Chat Room API tests for Geogram Desktop
///
/// This test suite tests the restricted chat room functionality with role-based
/// access control. It verifies member management, role promotion/demotion,
/// membership applications, and banning.
///
/// Usage:
///   dart tests/restricted_chat_test.dart [--port=PORT] [--host=HOST]
///
/// Prerequisites:
///   - Run from the geogram-desktop directory
///   - Geogram Desktop running with HTTP API enabled
///   - A chat collection loaded

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:bech32/bech32.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;

// Test configuration
int _testPort = 5678;
String _testHost = 'localhost';

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

void info(String message) {
  print('  [INFO] $message');
}

// ============================================================
// NOSTR Crypto Implementation (simplified for testing)
// ============================================================

class TestNostrKeyPair {
  final String privateKeyHex;
  final String publicKeyHex;

  TestNostrKeyPair({required this.privateKeyHex, required this.publicKeyHex});

  String get nsec => _encodeNsec(privateKeyHex);
  String get npub => _encodeNpub(publicKeyHex);
  String get callsign => 'X1${npub.substring(5, 9).toUpperCase()}';
}

final _secureRandom = SecureRandom('Fortuna')
  ..seed(KeyParameter(
    Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256))),
  ));

TestNostrKeyPair generateKeyPair() {
  final keyParams = ECKeyGeneratorParameters(ECCurve_secp256k1());
  final generator = ECKeyGenerator()
    ..init(ParametersWithRandom(keyParams, _secureRandom));

  final keyPair = generator.generateKeyPair();
  final privateKey = keyPair.privateKey as ECPrivateKey;
  final publicKey = keyPair.publicKey as ECPublicKey;

  final privateKeyBytes = _bigIntToBytes(privateKey.d!, 32);
  final publicKeyBytes = _bigIntToBytes(publicKey.Q!.x!.toBigInteger()!, 32);

  return TestNostrKeyPair(
    privateKeyHex: HEX.encode(privateKeyBytes),
    publicKeyHex: HEX.encode(publicKeyBytes),
  );
}

String _encodeNsec(String privateKeyHex) {
  final bytes = HEX.decode(privateKeyHex);
  final data = _convertBits(Uint8List.fromList(bytes), 8, 5, true);
  final bech32Data = Bech32('nsec', data);
  return const Bech32Codec().encode(bech32Data);
}

String _encodeNpub(String publicKeyHex) {
  final bytes = HEX.decode(publicKeyHex);
  final data = _convertBits(Uint8List.fromList(bytes), 8, 5, true);
  final bech32Data = Bech32('npub', data);
  return const Bech32Codec().encode(bech32Data);
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var temp = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (temp & BigInt.from(0xff)).toInt();
    temp = temp >> 8;
  }
  return bytes;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _convertBits(Uint8List data, int fromBits, int toBits, bool pad) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxv = (1 << toBits) - 1;

  for (final value in data) {
    acc = (acc << fromBits) | value;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) {
      result.add((acc << (toBits - bits)) & maxv);
    }
  }

  return Uint8List.fromList(result);
}

Uint8List _taggedHash(String tag, Uint8List data) {
  final tagHash = sha256.convert(utf8.encode(tag)).bytes;
  final input = Uint8List.fromList([...tagHash, ...tagHash, ...data]);
  return Uint8List.fromList(sha256.convert(input).bytes);
}

String schnorrSign(String messageHex, String privateKeyHex) {
  final messageBytes = HEX.decode(messageHex);
  final privateKeyBytes = HEX.decode(privateKeyHex);

  final d = _bytesToBigInt(Uint8List.fromList(privateKeyBytes));
  final curve = ECCurve_secp256k1();
  final n = curve.n;
  final G = curve.G;

  final P = G * d;
  final px = _bigIntToBytes(P!.x!.toBigInteger()!, 32);

  var dPrime = d;
  if (P.y!.toBigInteger()!.isOdd) {
    dPrime = n - d;
  }

  final auxRand = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    auxRand[i] = Random.secure().nextInt(256);
  }

  final dPrimeBytes = _bigIntToBytes(dPrime, 32);
  final auxHash = _taggedHash('BIP0340/aux', auxRand);
  final t = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    t[i] = dPrimeBytes[i] ^ auxHash[i];
  }

  final nonceInput = Uint8List.fromList([...t, ...px, ...messageBytes]);
  final kPrimeHash = _taggedHash('BIP0340/nonce', nonceInput);
  var kPrime = _bytesToBigInt(kPrimeHash) % n;

  if (kPrime == BigInt.zero) {
    throw Exception('Invalid nonce generated');
  }

  final R = G * kPrime;
  final rx = _bigIntToBytes(R!.x!.toBigInteger()!, 32);

  if (R.y!.toBigInteger()!.isOdd) {
    kPrime = n - kPrime;
  }

  final challengeInput = Uint8List.fromList([...rx, ...px, ...messageBytes]);
  final eHash = _taggedHash('BIP0340/challenge', challengeInput);
  final e = _bytesToBigInt(eHash) % n;

  final s = (kPrime + e * dPrime) % n;
  final sBytes = _bigIntToBytes(s, 32);

  final signature = Uint8List.fromList([...rx, ...sBytes]);
  return HEX.encode(signature);
}

// ============================================================
// NOSTR Event Creation
// ============================================================

Map<String, dynamic> createNostrEvent({
  required String pubkeyHex,
  required String content,
  required int kind,
  List<List<String>>? tags,
  int? createdAt,
}) {
  final event = {
    'pubkey': pubkeyHex,
    'created_at': createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    'kind': kind,
    'tags': tags ?? [],
    'content': content,
  };

  // Calculate event ID
  final serialized = jsonEncode([
    0,
    event['pubkey'],
    event['created_at'],
    event['kind'],
    event['tags'],
    event['content'],
  ]);
  final idHash = sha256.convert(utf8.encode(serialized));
  event['id'] = idHash.toString();

  return event;
}

Map<String, dynamic> signEvent(Map<String, dynamic> event, String privateKeyHex) {
  final id = event['id'] as String;
  event['sig'] = schnorrSign(id, privateKeyHex);
  return event;
}

String createAuthHeader(TestNostrKeyPair keyPair) {
  final event = createNostrEvent(
    pubkeyHex: keyPair.publicKeyHex,
    content: 'auth',
    kind: 1,
    tags: [['t', 'auth']],
  );
  signEvent(event, keyPair.privateKeyHex);
  final eventJson = jsonEncode(event);
  return 'Nostr ${base64Encode(utf8.encode(eventJson))}';
}

/// Create a signed NOSTR event for room management operations
Map<String, dynamic> createManagementEvent({
  required TestNostrKeyPair keyPair,
  required String action,
  required String roomId,
  String? targetNpub,
  String? role,
  String? callsign,
  String? message,
}) {
  final tags = <List<String>>[
    ['t', 'room-management'],
    ['action', action],
    ['room', roomId],
  ];

  if (targetNpub != null) {
    tags.add(['target', targetNpub]);
  }
  if (role != null) {
    tags.add(['role', role]);
  }
  if (callsign != null) {
    tags.add(['callsign', callsign]);
  }

  final event = createNostrEvent(
    pubkeyHex: keyPair.publicKeyHex,
    content: message ?? '$action request for $roomId',
    kind: 1,
    tags: tags,
  );

  return signEvent(event, keyPair.privateKeyHex);
}

/// Create Authorization header from a signed management event
String createManagementAuthHeader(Map<String, dynamic> event) {
  final eventJson = jsonEncode(event);
  return 'Nostr ${base64Encode(utf8.encode(eventJson))}';
}

// ============================================================
// Test State
// ============================================================

late TestNostrKeyPair _ownerKeyPair;
late TestNostrKeyPair _memberKeyPair;
late TestNostrKeyPair _outsiderKeyPair;
late TestNostrKeyPair _bannedKeyPair;
String? _deviceOwnerNpub;
String _restrictedRoomId = 'test-restricted-${DateTime.now().millisecondsSinceEpoch}';

// ============================================================
// HTTP Helpers
// ============================================================

Future<http.Response> apiGet(String endpoint, {String? authHeader}) async {
  final url = Uri.parse('http://$_testHost:$_testPort$endpoint');
  final headers = <String, String>{
    'Content-Type': 'application/json',
  };
  if (authHeader != null) {
    headers['Authorization'] = authHeader;
  }
  return await http.get(url, headers: headers);
}

Future<http.Response> apiPost(String endpoint, Map<String, dynamic> body, {String? authHeader}) async {
  final url = Uri.parse('http://$_testHost:$_testPort$endpoint');
  final headers = <String, String>{
    'Content-Type': 'application/json',
  };
  if (authHeader != null) {
    headers['Authorization'] = authHeader;
  }
  return await http.post(url, headers: headers, body: jsonEncode(body));
}

Future<http.Response> apiDelete(String endpoint, {String? authHeader, Map<String, dynamic>? body}) async {
  final url = Uri.parse('http://$_testHost:$_testPort$endpoint');
  final headers = <String, String>{
    'Content-Type': 'application/json',
  };
  if (authHeader != null) {
    headers['Authorization'] = authHeader;
  }
  final request = http.Request('DELETE', url);
  request.headers.addAll(headers);
  if (body != null) {
    request.body = jsonEncode(body);
  }
  final streamedResponse = await request.send();
  return await http.Response.fromStream(streamedResponse);
}

// ============================================================
// Tests
// ============================================================

Future<void> testCreateRestrictedRoom() async {
  print('\n--- Test: Create restricted room ---');

  try {
    // Create a restricted room via debug API (device owner only)
    final response = await apiPost('/api/debug', {
      'action': 'create_restricted_room',
      'room_id': _restrictedRoomId,
      'name': 'Test Restricted Room',
      'description': 'A room for testing restricted access',
      'owner_npub': _ownerKeyPair.npub,
    });

    info('Debug API response: ${response.statusCode} - ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Created restricted room');
        info('Room ID: $_restrictedRoomId');
        info('Owner: ${_ownerKeyPair.npub}');
      } else {
        fail('Create room', 'Response success=false: ${data['message']}');
      }
    } else if (response.statusCode == 500) {
      // Check if it's an internal error we can debug
      fail('Create room', 'Debug API error (500): ${response.body}');
    } else {
      // Try alternative - create room via chat service API
      info('Debug API not available (${response.statusCode}), trying direct room creation');

      // For now, we need to use an existing room or have debug API
      // If neither works, we'll skip the remaining tests
      final authHeader = createAuthHeader(_ownerKeyPair);
      final roomsResponse = await apiGet('/api/chat/', authHeader: authHeader);

      if (roomsResponse.statusCode == 200) {
        final roomsData = jsonDecode(roomsResponse.body);
        final rooms = roomsData['rooms'] as List;

        // Look for any existing restricted room or use 'main'
        for (final room in rooms) {
          if (room['visibility'] == 'RESTRICTED') {
            _restrictedRoomId = room['id'];
            info('Using existing restricted room: $_restrictedRoomId');
            pass('Found existing restricted room for testing');
            return;
          }
        }

        // If no restricted room exists, create one via the main room config
        // This requires device owner access
        info('No restricted room found - test may need manual room creation');
        fail('Create room', 'No debug API and no existing restricted rooms');
      } else {
        fail('Create room', 'Cannot list rooms: ${roomsResponse.statusCode}');
      }
    }

  } catch (e) {
    fail('Create restricted room test', 'Exception: $e');
  }
}

Future<void> testRestrictedRoomHiddenFromNonMembers() async {
  print('\n--- Test: Restricted room hidden from non-members ---');

  try {
    // Outsider should not see the restricted room in the list
    final authHeader = createAuthHeader(_outsiderKeyPair);
    final response = await apiGet('/api/chat/', authHeader: authHeader);

    if (response.statusCode != 200) {
      fail('List rooms', 'Expected 200, got ${response.statusCode}');
      return;
    }

    final data = jsonDecode(response.body);
    final rooms = data['rooms'] as List;

    // Check if our restricted room is visible
    final restrictedRoom = rooms.where((r) => r['id'] == _restrictedRoomId).toList();

    if (restrictedRoom.isEmpty) {
      pass('Restricted room is hidden from non-members');
    } else {
      fail('Room visibility', 'Non-member can see restricted room in list');
    }

  } catch (e) {
    fail('Room hidden test', 'Exception: $e');
  }
}

Future<void> testNonMemberCannotAccessRoom() async {
  print('\n--- Test: Non-member cannot access restricted room ---');

  try {
    // Outsider tries to read messages
    final authHeader = createAuthHeader(_outsiderKeyPair);
    final response = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: authHeader);

    if (response.statusCode == 403) {
      pass('Non-member correctly denied access (403)');

      final data = jsonDecode(response.body);
      if (data['hint'] != null) {
        info('Server hint: ${data['hint']}');
      }
    } else if (response.statusCode == 404) {
      pass('Non-member correctly denied - room appears to not exist (404)');
    } else if (response.statusCode == 200) {
      fail('Access control', 'Non-member can read restricted room messages!');
    } else {
      fail('Access control', 'Unexpected status: ${response.statusCode}');
    }

  } catch (e) {
    fail('Non-member access test', 'Exception: $e');
  }
}

Future<void> testOwnerCanAccessRoom() async {
  print('\n--- Test: Owner can access restricted room ---');

  try {
    final authHeader = createAuthHeader(_ownerKeyPair);
    final response = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: authHeader);

    if (response.statusCode == 200) {
      pass('Owner can access restricted room');

      final data = jsonDecode(response.body);
      info('Messages in room: ${(data['messages'] as List).length}');
    } else if (response.statusCode == 404) {
      info('Room not found - may need to create it first');
      fail('Owner access', 'Room does not exist');
    } else {
      fail('Owner access', 'Expected 200, got ${response.statusCode}');
    }

  } catch (e) {
    fail('Owner access test', 'Exception: $e');
  }
}

Future<void> testAddMember() async {
  print('\n--- Test: Owner adds member ---');

  try {
    // Owner adds a new member
    final event = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'add-member',
      roomId: _restrictedRoomId,
      targetNpub: _memberKeyPair.npub,
      callsign: _memberKeyPair.callsign,
    );

    // Use the management event as authorization header
    final authHeader = createManagementAuthHeader(event);
    final response = await apiPost('/api/chat/$_restrictedRoomId/members', {},
      authHeader: authHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Owner added member successfully');
        info('Added: ${_memberKeyPair.callsign} (${_memberKeyPair.npub})');
      } else {
        fail('Add member', 'Response success=false: ${data['message']}');
      }
    } else if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      fail('Add member', 'Permission denied: ${data['message']}');
    } else {
      fail('Add member', 'Expected 200, got ${response.statusCode}: ${response.body}');
    }

  } catch (e) {
    fail('Add member test', 'Exception: $e');
  }
}

Future<void> testMemberCanAccessRoom() async {
  print('\n--- Test: New member can access room ---');

  try {
    final authHeader = createAuthHeader(_memberKeyPair);
    final response = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: authHeader);

    if (response.statusCode == 200) {
      pass('New member can access restricted room');
    } else if (response.statusCode == 403) {
      fail('Member access', 'Member denied access after being added');
    } else {
      fail('Member access', 'Unexpected status: ${response.statusCode}');
    }

  } catch (e) {
    fail('Member access test', 'Exception: $e');
  }
}

Future<void> testMemberCanPostMessage() async {
  print('\n--- Test: Member can post message ---');

  try {
    // Member posts a signed message
    final event = createNostrEvent(
      pubkeyHex: _memberKeyPair.publicKeyHex,
      content: 'Test message from member at ${DateTime.now().toIso8601String()}',
      kind: 1,
      tags: [
        ['t', 'chat'],
        ['room', _restrictedRoomId],
        ['callsign', _memberKeyPair.callsign],
      ],
    );
    signEvent(event, _memberKeyPair.privateKeyHex);

    final response = await apiPost('/api/chat/$_restrictedRoomId/messages', {
      'event': event,
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Member posted message successfully');
        info('Author: ${data['author']}');
      } else {
        fail('Post message', 'Response success=false: ${data['message']}');
      }
    } else if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      if (data['message']?.contains('read-only') == true) {
        info('Room is read-only - posting not allowed');
        pass('Correctly denied write to read-only room');
      } else {
        fail('Post message', 'Permission denied: ${data['message']}');
      }
    } else {
      fail('Post message', 'Expected 200, got ${response.statusCode}');
    }

  } catch (e) {
    fail('Member post message test', 'Exception: $e');
  }
}

Future<void> testGetRoomRoles() async {
  print('\n--- Test: Get room roles ---');

  try {
    final authHeader = createAuthHeader(_ownerKeyPair);
    final response = await apiGet('/api/chat/$_restrictedRoomId/roles', authHeader: authHeader);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      pass('Retrieved room roles');

      info('Owner: ${data['owner']}');
      info('Admins: ${(data['admins'] as List).length}');
      info('Moderators: ${(data['moderators'] as List).length}');
      info('Members: ${(data['members'] as List).length}');

      // Verify our member is in the list
      final members = data['members'] as List;
      if (members.contains(_memberKeyPair.npub)) {
        pass('Added member appears in member list');
      } else {
        info('Member npub: ${_memberKeyPair.npub}');
        info('Member list: $members');
        fail('Member list', 'Added member not in member list');
      }
    } else {
      fail('Get roles', 'Expected 200, got ${response.statusCode}');
    }

  } catch (e) {
    fail('Get room roles test', 'Exception: $e');
  }
}

Future<void> testPromoteToModerator() async {
  print('\n--- Test: Promote member to moderator ---');

  try {
    final event = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'promote',
      roomId: _restrictedRoomId,
      targetNpub: _memberKeyPair.npub,
      role: 'moderator',
    );

    final authHeader = createManagementAuthHeader(event);
    final response = await apiPost('/api/chat/$_restrictedRoomId/promote', {},
      authHeader: authHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Promoted member to moderator');
        info('New role: ${data['role']}');
      } else {
        fail('Promote', 'Response success=false: ${data['message']}');
      }
    } else {
      fail('Promote', 'Expected 200, got ${response.statusCode}: ${response.body}');
    }

  } catch (e) {
    fail('Promote to moderator test', 'Exception: $e');
  }
}

Future<void> testModeratorCanAddMembers() async {
  print('\n--- Test: Moderator can add members ---');

  try {
    // Moderator (formerly member) tries to add a new user
    final newMember = generateKeyPair();

    final event = createManagementEvent(
      keyPair: _memberKeyPair, // Now a moderator
      action: 'add-member',
      roomId: _restrictedRoomId,
      targetNpub: newMember.npub,
      callsign: newMember.callsign,
    );

    final authHeader = createManagementAuthHeader(event);
    final response = await apiPost('/api/chat/$_restrictedRoomId/members', {},
      authHeader: authHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Moderator added new member');
      } else {
        fail('Mod add member', 'Response success=false: ${data['message']}');
      }
    } else if (response.statusCode == 403) {
      fail('Mod add member', 'Moderator cannot add members - permission issue');
    } else {
      fail('Mod add member', 'Expected 200, got ${response.statusCode}');
    }

  } catch (e) {
    fail('Moderator add member test', 'Exception: $e');
  }
}

Future<void> testBanUser() async {
  print('\n--- Test: Ban user ---');

  try {
    // First add the user we want to ban as a member
    final addEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'add-member',
      roomId: _restrictedRoomId,
      targetNpub: _bannedKeyPair.npub,
      callsign: _bannedKeyPair.callsign,
    );

    final addAuthHeader = createManagementAuthHeader(addEvent);
    await apiPost('/api/chat/$_restrictedRoomId/members', {},
      authHeader: addAuthHeader,
    );

    // Now ban them
    final banEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'ban',
      roomId: _restrictedRoomId,
      targetNpub: _bannedKeyPair.npub,
    );

    final banAuthHeader = createManagementAuthHeader(banEvent);
    final response = await apiPost('/api/chat/$_restrictedRoomId/ban/${_bannedKeyPair.npub}', {},
      authHeader: banAuthHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Banned user');
        info('Banned: ${_bannedKeyPair.callsign}');
      } else {
        fail('Ban user', 'Response success=false: ${data['message']}');
      }
    } else {
      fail('Ban user', 'Expected 200, got ${response.statusCode}: ${response.body}');
    }

  } catch (e) {
    fail('Ban user test', 'Exception: $e');
  }
}

Future<void> testBannedUserCannotAccess() async {
  print('\n--- Test: Banned user cannot access room ---');

  try {
    final authHeader = createAuthHeader(_bannedKeyPair);
    final response = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: authHeader);

    if (response.statusCode == 403) {
      pass('Banned user correctly denied access');
    } else if (response.statusCode == 200) {
      fail('Ban enforcement', 'Banned user can still access room!');
    } else {
      info('Status: ${response.statusCode}');
      pass('Banned user denied access');
    }

  } catch (e) {
    fail('Banned user access test', 'Exception: $e');
  }
}

Future<void> testMembershipApplication() async {
  print('\n--- Test: Membership application flow ---');

  try {
    // Outsider applies for membership
    final applyEvent = createManagementEvent(
      keyPair: _outsiderKeyPair,
      action: 'apply',
      roomId: _restrictedRoomId,
      callsign: _outsiderKeyPair.callsign,
      message: 'I would like to join this room',
    );

    final applyAuthHeader = createManagementAuthHeader(applyEvent);
    final applyResponse = await apiPost('/api/chat/$_restrictedRoomId/apply', {},
      authHeader: applyAuthHeader,
    );

    if (applyResponse.statusCode == 200) {
      final data = jsonDecode(applyResponse.body);
      if (data['success'] == true || data['status'] == 'pending') {
        pass('Application submitted');
        info('Status: ${data['status']}');
      } else {
        fail('Apply', 'Response: ${data['message']}');
        return;
      }
    } else if (applyResponse.statusCode == 403) {
      // Room might not accept applications - that's a valid configuration
      info('Room does not accept applications');
      pass('Application endpoint responds correctly');
      return;
    } else {
      fail('Apply', 'Expected 200, got ${applyResponse.statusCode}');
      return;
    }

    // Owner/moderator checks pending applications
    final authHeader = createAuthHeader(_ownerKeyPair);
    final listResponse = await apiGet('/api/chat/$_restrictedRoomId/applicants', authHeader: authHeader);

    if (listResponse.statusCode == 200) {
      final data = jsonDecode(listResponse.body);
      final applicants = data['applicants'] as List;
      pass('Listed pending applicants');
      info('Pending count: ${applicants.length}');

      // Verify our applicant is in the list
      final ourApplicant = applicants.where(
        (a) => a['npub'] == _outsiderKeyPair.npub
      ).toList();

      if (ourApplicant.isNotEmpty) {
        pass('Applicant appears in pending list');
      } else {
        info('Applicant npub: ${_outsiderKeyPair.npub}');
        fail('Applicant list', 'Our applicant not in pending list');
      }
    } else {
      fail('List applicants', 'Expected 200, got ${listResponse.statusCode}');
    }

    // Approve the application
    final approveEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'approve',
      roomId: _restrictedRoomId,
      targetNpub: _outsiderKeyPair.npub,
    );

    final approveAuthHeader = createManagementAuthHeader(approveEvent);
    final approveResponse = await apiPost('/api/chat/$_restrictedRoomId/approve/${_outsiderKeyPair.npub}', {},
      authHeader: approveAuthHeader,
    );

    if (approveResponse.statusCode == 200) {
      final data = jsonDecode(approveResponse.body);
      if (data['success'] == true) {
        pass('Application approved');
      } else {
        fail('Approve', 'Response: ${data['message']}');
        return;
      }
    } else {
      fail('Approve', 'Expected 200, got ${approveResponse.statusCode}');
      return;
    }

    // Verify the formerly-outsider can now access the room
    final outsiderAuth = createAuthHeader(_outsiderKeyPair);
    final accessResponse = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: outsiderAuth);

    if (accessResponse.statusCode == 200) {
      pass('Approved applicant can now access room');
    } else {
      fail('Post-approval access', 'Approved user cannot access room');
    }

  } catch (e) {
    fail('Membership application test', 'Exception: $e');
  }
}

Future<void> testRemoveMember() async {
  print('\n--- Test: Remove member ---');

  try {
    // First, get the list of members to confirm our target is there
    final authHeader = createAuthHeader(_ownerKeyPair);
    final rolesResponse = await apiGet('/api/chat/$_restrictedRoomId/roles', authHeader: authHeader);

    if (rolesResponse.statusCode != 200) {
      fail('Remove member', 'Cannot get roles to verify member');
      return;
    }

    // Remove a member (the approved outsider)
    final removeEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'remove-member',
      roomId: _restrictedRoomId,
      targetNpub: _outsiderKeyPair.npub,
    );

    final removeAuthHeader = createManagementAuthHeader(removeEvent);
    final response = await apiDelete('/api/chat/$_restrictedRoomId/members/${_outsiderKeyPair.npub}',
      authHeader: removeAuthHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Removed member');
      } else {
        fail('Remove member', 'Response: ${data['message']}');
        return;
      }
    } else {
      fail('Remove member', 'Expected 200, got ${response.statusCode}');
      return;
    }

    // Verify removed member cannot access room
    final removedAuth = createAuthHeader(_outsiderKeyPair);
    final accessResponse = await apiGet('/api/chat/$_restrictedRoomId/messages', authHeader: removedAuth);

    if (accessResponse.statusCode == 403 || accessResponse.statusCode == 404) {
      pass('Removed member cannot access room');
    } else if (accessResponse.statusCode == 200) {
      fail('Removal enforcement', 'Removed member can still access room!');
    } else {
      info('Status: ${accessResponse.statusCode}');
      pass('Removed member appropriately denied');
    }

  } catch (e) {
    fail('Remove member test', 'Exception: $e');
  }
}

Future<void> testUnbanUser() async {
  print('\n--- Test: Unban user ---');

  try {
    final unbanEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'unban',
      roomId: _restrictedRoomId,
      targetNpub: _bannedKeyPair.npub,
    );

    final unbanAuthHeader = createManagementAuthHeader(unbanEvent);
    final response = await apiDelete('/api/chat/$_restrictedRoomId/ban/${_bannedKeyPair.npub}',
      authHeader: unbanAuthHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Unbanned user');
      } else {
        fail('Unban', 'Response: ${data['message']}');
        return;
      }
    } else {
      fail('Unban', 'Expected 200, got ${response.statusCode}');
      return;
    }

    // Note: Unbanned user still needs to be re-added as member to access room
    info('Unbanned user must be re-added as member to access room');

  } catch (e) {
    fail('Unban user test', 'Exception: $e');
  }
}

Future<void> testDemoteModerator() async {
  print('\n--- Test: Demote moderator ---');

  try {
    final demoteEvent = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'demote',
      roomId: _restrictedRoomId,
      targetNpub: _memberKeyPair.npub, // Our promoted moderator
    );

    final demoteAuthHeader = createManagementAuthHeader(demoteEvent);
    final response = await apiPost('/api/chat/$_restrictedRoomId/demote', {},
      authHeader: demoteAuthHeader,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        pass('Demoted moderator to member');
        info('New role: ${data['role'] ?? 'member'}');
      } else {
        fail('Demote', 'Response: ${data['message']}');
      }
    } else {
      fail('Demote', 'Expected 200, got ${response.statusCode}');
    }

  } catch (e) {
    fail('Demote moderator test', 'Exception: $e');
  }
}

Future<void> testNonOwnerCannotPromoteToAdmin() async {
  print('\n--- Test: Non-owner cannot promote to admin ---');

  try {
    // Moderator tries to promote someone to admin (should fail)
    final promoteEvent = createManagementEvent(
      keyPair: _memberKeyPair, // Not the owner
      action: 'promote',
      roomId: _restrictedRoomId,
      targetNpub: _outsiderKeyPair.npub,
      role: 'admin',
    );

    final promoteAuthHeader = createManagementAuthHeader(promoteEvent);
    final response = await apiPost('/api/chat/$_restrictedRoomId/promote', {},
      authHeader: promoteAuthHeader,
    );

    if (response.statusCode == 403) {
      pass('Non-owner correctly denied admin promotion');
    } else if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == false) {
        pass('Non-owner admin promotion rejected');
      } else {
        fail('Admin promotion', 'Non-owner was able to promote to admin!');
      }
    } else {
      info('Status: ${response.statusCode}');
      pass('Non-owner admin promotion appropriately handled');
    }

  } catch (e) {
    fail('Non-owner promote test', 'Exception: $e');
  }
}

Future<void> testReplayAttackPrevention() async {
  print('\n--- Test: Replay attack prevention ---');

  try {
    // Create an event with old timestamp (>5 minutes ago)
    final oldTimestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 600; // 10 minutes ago

    final tags = <List<String>>[
      ['t', 'room-management'],
      ['action', 'add-member'],
      ['room', _restrictedRoomId],
      ['target', generateKeyPair().npub],
    ];

    final oldEvent = createNostrEvent(
      pubkeyHex: _ownerKeyPair.publicKeyHex,
      content: 'Old add-member request',
      kind: 1,
      tags: tags,
      createdAt: oldTimestamp,
    );
    signEvent(oldEvent, _ownerKeyPair.privateKeyHex);

    final response = await apiPost('/api/chat/$_restrictedRoomId/members', {
      'event': oldEvent,
    });

    if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      if (data['message']?.toString().toLowerCase().contains('expired') == true ||
          data['message']?.toString().toLowerCase().contains('replay') == true ||
          data['message']?.toString().toLowerCase().contains('timestamp') == true) {
        pass('Old event correctly rejected (replay attack prevented)');
      } else {
        pass('Old event rejected');
        info('Reason: ${data['message']}');
      }
    } else if (response.statusCode == 200) {
      fail('Replay prevention', 'Server accepted event with old timestamp!');
    } else {
      info('Status: ${response.statusCode}');
      pass('Old event appropriately rejected');
    }

  } catch (e) {
    fail('Replay attack test', 'Exception: $e');
  }
}

Future<void> testWrongRoomTagPrevention() async {
  print('\n--- Test: Wrong room tag prevention ---');

  try {
    // Create an event with a different room in the tag
    final event = createManagementEvent(
      keyPair: _ownerKeyPair,
      action: 'add-member',
      roomId: 'different-room-id', // Wrong room!
      targetNpub: generateKeyPair().npub,
    );

    // But send it to our actual room endpoint
    final authHeader = createManagementAuthHeader(event);
    final response = await apiPost('/api/chat/$_restrictedRoomId/members', {},
      authHeader: authHeader,
    );

    if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      if (data['message']?.toString().toLowerCase().contains('room') == true ||
          data['message']?.toString().toLowerCase().contains('mismatch') == true) {
        pass('Room mismatch correctly rejected');
      } else {
        pass('Mismatched room event rejected');
        info('Reason: ${data['message']}');
      }
    } else if (response.statusCode == 200) {
      fail('Room verification', 'Server accepted event with wrong room tag!');
    } else {
      info('Status: ${response.statusCode}');
      pass('Wrong room event appropriately rejected');
    }

  } catch (e) {
    fail('Wrong room tag test', 'Exception: $e');
  }
}

// ============================================================
// Main
// ============================================================

Future<void> main(List<String> args) async {
  print('');
  print('=' * 60);
  print('Geogram Desktop Restricted Chat Room Test Suite');
  print('=' * 60);
  print('');

  // Parse arguments
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      _testPort = int.tryParse(arg.substring(7)) ?? _testPort;
    } else if (arg.startsWith('--host=')) {
      _testHost = arg.substring(7);
    }
  }

  print('Target: http://$_testHost:$_testPort');
  print('');

  // Generate test key pairs
  print('Generating test key pairs...');
  _ownerKeyPair = generateKeyPair();
  _memberKeyPair = generateKeyPair();
  _outsiderKeyPair = generateKeyPair();
  _bannedKeyPair = generateKeyPair();

  print('Owner npub:    ${_ownerKeyPair.npub}');
  print('Member npub:   ${_memberKeyPair.npub}');
  print('Outsider npub: ${_outsiderKeyPair.npub}');
  print('Banned npub:   ${_bannedKeyPair.npub}');
  print('');

  // Check if server is available
  print('Connecting to server...');
  try {
    final healthCheck = await apiGet('/api/').timeout(const Duration(seconds: 5));
    if (healthCheck.statusCode != 200) {
      print('');
      print('[ERROR] Server not responding correctly at http://$_testHost:$_testPort');
      print('   Make sure Geogram Desktop is running with HTTP API enabled.');
      print('   Response: ${healthCheck.statusCode}');
      exit(1);
    }
    print('[OK] Server is running');

    final serverInfo = jsonDecode(healthCheck.body);
    print('  Service: ${serverInfo['service']}');
    print('  Version: ${serverInfo['version']}');
    print('  Callsign: ${serverInfo['callsign']}');

    // Store device owner npub for reference
    _deviceOwnerNpub = serverInfo['npub'];
    if (_deviceOwnerNpub != null) {
      print('  Device owner: $_deviceOwnerNpub');
    }

  } catch (e) {
    print('');
    print('[ERROR] Cannot connect to server at http://$_testHost:$_testPort');
    print('   Error: $e');
    print('');
    print('   Please start Geogram Desktop with:');
    print('     --port=$_testPort');
    print('   And enable HTTP API in Security settings.');
    exit(1);
  }

  // Check if chat API is available
  try {
    final chatCheck = await apiGet('/api/chat/');
    if (chatCheck.statusCode != 200) {
      print('');
      print('[ERROR] Chat API not available');
      print('   Make sure a chat collection is loaded.');
      print('   Response: ${chatCheck.statusCode}');
      exit(1);
    }

    final chatData = jsonDecode(chatCheck.body);
    final rooms = chatData['rooms'] as List;
    print('[OK] Chat API available (${rooms.length} rooms visible)');

  } catch (e) {
    print('');
    print('[ERROR] Error checking chat API: $e');
    exit(1);
  }

  print('');

  // Run tests
  await testCreateRestrictedRoom();
  await testRestrictedRoomHiddenFromNonMembers();
  await testNonMemberCannotAccessRoom();
  await testOwnerCanAccessRoom();
  await testAddMember();
  await testMemberCanAccessRoom();
  await testMemberCanPostMessage();
  await testGetRoomRoles();
  await testPromoteToModerator();
  await testModeratorCanAddMembers();
  await testBanUser();
  await testBannedUserCannotAccess();
  await testMembershipApplication();
  await testRemoveMember();
  await testUnbanUser();
  await testDemoteModerator();
  await testNonOwnerCannotPromoteToAdmin();
  await testReplayAttackPrevention();
  await testWrongRoomTagPrevention();

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
}
