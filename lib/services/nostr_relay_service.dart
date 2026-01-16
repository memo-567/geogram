/*
 * NOSTR relay service (NIP-01 + optional NIP-42 for writes).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../util/nostr_event.dart';
import 'nostr_blossom_service.dart';
import 'nostr_relay_storage.dart';

typedef NostrSend = void Function(String message);

class NostrRelayService {
  final NostrRelayStorage _storage;
  final NostrBlossomService? _blossom;
  final bool replicateBlossom;
  final Map<String, _RelayConnection> _connections = {};
  final Random _rng = Random.secure();

  bool requireAuthForWrites;
  Set<String> allowedPubkeysHex;

  NostrRelayService({
    required NostrRelayStorage storage,
    NostrBlossomService? blossom,
    this.requireAuthForWrites = true,
    Set<String>? allowedPubkeysHex,
    this.replicateBlossom = true,
  })  : _storage = storage,
        _blossom = blossom,
        allowedPubkeysHex = allowedPubkeysHex ?? {};

  void registerConnection(
    String connectionId,
    NostrSend send, {
    bool openRelay = false,
  }) {
    final challenge = _generateChallenge();
    final connection = _RelayConnection(
      id: connectionId,
      send: send,
      openRelay: openRelay,
      challenge: challenge,
    );
    _connections[connectionId] = connection;
    if (requireAuthForWrites && !openRelay) {
      connection.send(jsonEncode(['AUTH', challenge]));
    }
  }

  void unregisterConnection(String connectionId) {
    _connections.remove(connectionId);
  }

  void updateAllowedPubkeys(Set<String> pubkeysHex) {
    allowedPubkeysHex = pubkeysHex;
  }

  void handleFrame(String connectionId, dynamic frame) {
    final connection = _connections[connectionId];
    if (connection == null) return;
    if (frame is! List || frame.isEmpty) return;

    final type = frame[0]?.toString();
    if (type == null) return;

    switch (type) {
      case 'EVENT':
        _handleEvent(connection, frame);
        break;
      case 'REQ':
        _handleReq(connection, frame);
        break;
      case 'CLOSE':
        _handleClose(connection, frame);
        break;
      case 'AUTH':
        _handleAuth(connection, frame);
        break;
      default:
        break;
    }
  }

  void _handleAuth(_RelayConnection connection, List<dynamic> frame) {
    if (frame.length < 2) return;
    final eventJson = frame[1];
    if (eventJson is! Map<String, dynamic>) return;

    try {
      final event = NostrEvent.fromJson(eventJson);
      final eventId = event.id ?? event.calculateId();
      if (!event.verify()) {
        connection.send(jsonEncode(['OK', eventId, false, 'invalid: signature']));
        return;
      }
      if (!_isFresh(event)) {
        connection.send(jsonEncode(['OK', eventId, false, 'invalid: stale']));
        return;
      }
      final challenge = event.getTagValue('challenge');
      if (challenge == null || challenge != connection.challenge) {
        connection.send(jsonEncode(['OK', eventId, false, 'invalid: challenge']));
        return;
      }
      connection.authedPubkey = event.pubkey;
      connection.send(jsonEncode(['OK', eventId, true, '']));
    } catch (e) {
      connection.send(jsonEncode(['NOTICE', 'Auth error: $e']));
    }
  }

  void _handleEvent(_RelayConnection connection, List<dynamic> frame) {
    if (frame.length < 2) return;
    final eventJson = frame[1];
    if (eventJson is! Map<String, dynamic>) return;

    try {
      final event = NostrEvent.fromJson(eventJson);
      final eventId = event.id ?? event.calculateId();
      if (!event.verify()) {
        connection.send(jsonEncode(['OK', eventId, false, 'invalid: signature']));
        return;
      }

      if (!_canWrite(connection, event.pubkey)) {
        connection.send(jsonEncode(['OK', eventId, false, 'restricted: write']));
        return;
      }

      _storage.storeEvent(event, jsonEncode(eventJson));
      connection.send(jsonEncode(['OK', eventId, true, '']));
      _broadcastEvent(eventJson);
      _maybeReplicateBlobs(eventJson, event.pubkey);
    } catch (e) {
      connection.send(jsonEncode(['NOTICE', 'Event error: $e']));
    }
  }

  void _handleReq(_RelayConnection connection, List<dynamic> frame) {
    if (frame.length < 2) return;
    final subId = frame[1]?.toString();
    if (subId == null || subId.isEmpty) return;

    final filters = <Map<String, dynamic>>[];
    for (var i = 2; i < frame.length; i++) {
      final filter = frame[i];
      if (filter is Map<String, dynamic>) {
        filters.add(filter);
      }
    }

    connection.subscriptions[subId] = filters;

    final events = _storage.queryEvents(filters);
    for (final event in events) {
      connection.send(jsonEncode(['EVENT', subId, event]));
    }
    connection.send(jsonEncode(['EOSE', subId]));
  }

  void _handleClose(_RelayConnection connection, List<dynamic> frame) {
    if (frame.length < 2) return;
    final subId = frame[1]?.toString();
    if (subId == null) return;
    connection.subscriptions.remove(subId);
  }

  void _broadcastEvent(Map<String, dynamic> eventJson) {
    for (final connection in _connections.values) {
      for (final entry in connection.subscriptions.entries) {
        final subId = entry.key;
        final filters = entry.value;
        if (_matchesFilters(eventJson, filters)) {
          connection.send(jsonEncode(['EVENT', subId, eventJson]));
        }
      }
    }
  }

  bool _matchesFilters(Map<String, dynamic> event, List<Map<String, dynamic>> filters) {
    for (final filter in filters) {
      if (_matchesFilter(event, filter)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesFilter(Map<String, dynamic> event, Map<String, dynamic> filter) {
    final id = event['id']?.toString();
    final pubkey = event['pubkey']?.toString();
    final createdAt = int.tryParse(event['created_at']?.toString() ?? '');
    final kind = int.tryParse(event['kind']?.toString() ?? '');

    final ids = _stringList(filter['ids']);
    if (ids.isNotEmpty && (id == null || !ids.contains(id))) return false;

    final authors = _stringList(filter['authors']);
    if (authors.isNotEmpty && (pubkey == null || !authors.contains(pubkey))) return false;

    final kinds = _intList(filter['kinds']);
    if (kinds.isNotEmpty && (kind == null || !kinds.contains(kind))) return false;

    final since = _intValue(filter['since']);
    if (since != null && (createdAt == null || createdAt < since)) return false;

    final until = _intValue(filter['until']);
    if (until != null && (createdAt == null || createdAt > until)) return false;

    final tagFilters = <String, List<String>>{};
    for (final entry in filter.entries) {
      if (entry.key.startsWith('#')) {
        tagFilters[entry.key.substring(1)] = _stringList(entry.value);
      }
    }
    if (!_matchesTags(event, tagFilters)) return false;

    return true;
  }

  bool _matchesTags(Map<String, dynamic> event, Map<String, List<String>> tagFilters) {
    if (tagFilters.isEmpty) return true;
    final tags = event['tags'] as List<dynamic>? ?? [];
    final tagMap = <String, Set<String>>{};
    for (final tagEntry in tags) {
      if (tagEntry is! List || tagEntry.isEmpty) continue;
      final tagName = tagEntry[0]?.toString();
      final value = tagEntry.length > 1 ? tagEntry[1]?.toString() : null;
      if (tagName == null || value == null) continue;
      tagMap.putIfAbsent(tagName, () => <String>{}).add(value);
    }
    for (final entry in tagFilters.entries) {
      final wanted = entry.value;
      if (wanted.isEmpty) continue;
      final present = tagMap[entry.key];
      if (present == null) return false;
      if (!present.any(wanted.contains)) return false;
    }
    return true;
  }

  bool _canWrite(_RelayConnection connection, String pubkeyHex) {
    if (connection.openRelay) return true;
    if (requireAuthForWrites) {
      if (connection.authedPubkey != pubkeyHex) return false;
    }
    return allowedPubkeysHex.contains(pubkeyHex);
  }

  void _maybeReplicateBlobs(Map<String, dynamic> eventJson, String pubkeyHex) {
    if (_blossom == null || !replicateBlossom) return;
    if (!allowedPubkeysHex.contains(pubkeyHex)) return;
    final urls = _extractUrls(eventJson);
    for (final url in urls) {
      final hash = _extractBlossomHash(url);
      if (hash != null) {
        _blossom!.addReference(hash: hash, eventId: eventJson['id']?.toString(), pubkey: pubkeyHex);
        continue;
      }
      unawaited(_blossom!.replicateUrl(url, ownerPubkey: pubkeyHex));
    }
  }

  bool _isFresh(NostrEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (now - event.createdAt).abs() <= 300;
  }

  String _generateChallenge() {
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_rng.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  static List<int> _intList(dynamic value) {
    if (value is List) {
      return value.map((e) => int.tryParse(e.toString()) ?? 0).toList();
    }
    return [];
  }

  static int? _intValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static List<String> _extractUrls(Map<String, dynamic> eventJson) {
    final urls = <String>{};
    final tags = eventJson['tags'] as List<dynamic>? ?? [];
    for (final tagEntry in tags) {
      if (tagEntry is! List || tagEntry.isEmpty) continue;
      final name = tagEntry[0]?.toString();
      if (name == 'url' && tagEntry.length > 1) {
        urls.add(tagEntry[1].toString());
      }
      if (name == 'imeta') {
        for (var i = 1; i < tagEntry.length; i++) {
          final value = tagEntry[i]?.toString() ?? '';
          if (value.startsWith('url ')) {
            urls.add(value.substring(4));
          }
        }
      }
    }
    return urls.toList();
  }

  static String? _extractBlossomHash(String url) {
    if (url.startsWith('blossom://')) {
      return url.substring('blossom://'.length);
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last;
    if (last.length == 64 && RegExp(r'^[a-fA-F0-9]+$').hasMatch(last)) {
      return last.toLowerCase();
    }
    return null;
  }
}

class _RelayConnection {
  final String id;
  final NostrSend send;
  final bool openRelay;
  final String challenge;
  String? authedPubkey;
  final Map<String, List<Map<String, dynamic>>> subscriptions = {};

  _RelayConnection({
    required this.id,
    required this.send,
    required this.openRelay,
    required this.challenge,
  });
}
