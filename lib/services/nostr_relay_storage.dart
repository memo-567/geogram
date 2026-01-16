/*
 * SQLite-backed NOSTR relay storage.
 */

import 'dart:convert';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../util/nostr_event.dart';
import 'nostr_storage_paths.dart';
import 'sqlite_loader.dart';

class NostrRelayStorage {
  final Database _db;

  NostrRelayStorage._(this._db);

  static NostrRelayStorage open({String? baseDir}) {
    final dir = Directory(NostrStoragePaths.baseDir(overrideBase: baseDir));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final dbPath = NostrStoragePaths.relayDbPath(overrideBase: baseDir);
    final db = SQLiteLoader.openDatabase(dbPath);
    final storage = NostrRelayStorage._(db);
    storage._init();
    return storage;
  }

  void _init() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        pubkey TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        kind INTEGER NOT NULL,
        content TEXT NOT NULL,
        sig TEXT NOT NULL,
        raw TEXT NOT NULL,
        deleted_at INTEGER,
        replaced_by TEXT
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS event_tags (
        event_id TEXT NOT NULL,
        idx INTEGER NOT NULL,
        tag TEXT NOT NULL,
        value TEXT NOT NULL,
        other TEXT
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS event_refs (
        event_id TEXT NOT NULL,
        ref_type TEXT NOT NULL,
        ref TEXT NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS events_kind_created_at_idx
      ON events(kind, created_at DESC);
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS events_pubkey_created_at_idx
      ON events(pubkey, created_at DESC);
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS events_deleted_idx
      ON events(deleted_at);
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS event_tags_tag_value_idx
      ON event_tags(tag, value);
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS event_refs_ref_idx
      ON event_refs(ref_type, ref);
    ''');
  }

  void close() {
    _db.dispose();
  }

  void storeEvent(NostrEvent event, String rawJson) {
    final eventId = event.id ?? event.calculateId();
    final sig = event.sig ?? '';
    if (sig.isEmpty) {
      throw StateError('Event signature missing');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _db.execute('BEGIN');
    try {
      _db.execute(
        '''
        INSERT OR REPLACE INTO events (
          id, pubkey, created_at, kind, content, sig, raw, deleted_at, replaced_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE(
          (SELECT deleted_at FROM events WHERE id = ?),
          NULL
        ), COALESCE(
          (SELECT replaced_by FROM events WHERE id = ?),
          NULL
        ));
        ''',
        [
          eventId,
          event.pubkey,
          event.createdAt,
          event.kind,
          event.content,
          sig,
          rawJson,
          eventId,
          eventId,
        ],
      );

      _db.execute('DELETE FROM event_tags WHERE event_id = ?', [eventId]);
      _db.execute('DELETE FROM event_refs WHERE event_id = ?', [eventId]);

      for (var i = 0; i < event.tags.length; i++) {
        final tag = event.tags[i];
        if (tag.isEmpty) continue;
        final tagName = tag[0];
        final value = tag.length > 1 ? tag[1] : '';
        final other = tag.length > 2 ? jsonEncode(tag.sublist(2)) : null;
        _db.execute(
          'INSERT INTO event_tags (event_id, idx, tag, value, other) VALUES (?, ?, ?, ?, ?)',
          [eventId, i, tagName, value, other],
        );
        if (tagName == 'e' || tagName == 'p' || tagName == 'a') {
          _db.execute(
            'INSERT INTO event_refs (event_id, ref_type, ref) VALUES (?, ?, ?)',
            [eventId, tagName, value],
          );
        }
      }

      if (event.kind == NostrEventKind.deletion) {
        _applyDeletion(event, now);
      } else if (_isReplaceableKind(event.kind)) {
        _applyReplaceable(event, now);
      }

      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, dynamic>> queryEvents(List<Map<String, dynamic>> filters) {
    final results = <Map<String, dynamic>>[];

    for (final filter in filters) {
      final ids = _stringList(filter['ids']);
      final authors = _stringList(filter['authors']);
      final kinds = _intList(filter['kinds']);
      final since = _intValue(filter['since']);
      final until = _intValue(filter['until']);
      final limit = _intValue(filter['limit']) ?? 200;

      final tagFilters = <String, List<String>>{};
      for (final entry in filter.entries) {
        final key = entry.key;
        if (key.startsWith('#')) {
          tagFilters[key.substring(1)] = _stringList(entry.value);
        }
      }

      final whereClauses = <String>['deleted_at IS NULL'];
      final args = <Object?>[];

      if (ids.isNotEmpty) {
        whereClauses.add('id IN (${_placeholders(ids.length)})');
        args.addAll(ids);
      }
      if (authors.isNotEmpty) {
        whereClauses.add('pubkey IN (${_placeholders(authors.length)})');
        args.addAll(authors);
      }
      if (kinds.isNotEmpty) {
        whereClauses.add('kind IN (${_placeholders(kinds.length)})');
        args.addAll(kinds);
      }
      if (since != null) {
        whereClauses.add('created_at >= ?');
        args.add(since);
      }
      if (until != null) {
        whereClauses.add('created_at <= ?');
        args.add(until);
      }

      final sql = '''
        SELECT raw FROM events
        WHERE ${whereClauses.join(' AND ')}
        ORDER BY created_at DESC
        LIMIT ?
      ''';
      args.add(limit);

      final rows = _db.select(sql, args);
      for (final row in rows) {
        final raw = row['raw'] as String;
        final event = jsonDecode(raw) as Map<String, dynamic>;
        if (!_matchesTags(event, tagFilters)) {
          continue;
        }
        results.add(event);
      }
    }

    return results;
  }

  void _applyDeletion(NostrEvent event, int deletedAt) {
    final targetIds = <String>[];
    for (final tag in event.tags) {
      if (tag.isNotEmpty && tag[0] == 'e' && tag.length > 1) {
        targetIds.add(tag[1]);
      }
    }
    if (targetIds.isEmpty) return;

    _db.execute(
      'UPDATE events SET deleted_at = ? WHERE id IN (${_placeholders(targetIds.length)})',
      [deletedAt, ...targetIds],
    );
  }

  void _applyReplaceable(NostrEvent event, int _now) {
    final dTag = _findTagValue(event.tags, 'd');
    final params = <Object?>[event.pubkey, event.kind];
    final clauses = <String>[
      'pubkey = ?',
      'kind = ?',
      'id != ?',
      'deleted_at IS NULL',
    ];
    params.add(event.id);

    if (_isParameterizedReplaceable(event.kind) && dTag != null) {
      clauses.add('id IN (SELECT event_id FROM event_tags WHERE tag = ? AND value = ?)');
      params.addAll(['d', dTag]);
    }

    final sql = '''
      UPDATE events
      SET replaced_by = ?
      WHERE ${clauses.join(' AND ')}
    ''';
    _db.execute(sql, [event.id, ...params]);
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

  static bool _isReplaceableKind(int kind) {
    return kind == 0 ||
        kind == 3 ||
        (kind >= 10000 && kind < 20000) ||
        (kind >= 30000 && kind < 40000);
  }

  static bool _isParameterizedReplaceable(int kind) {
    return kind >= 30000 && kind < 40000;
  }

  static String? _findTagValue(List<List<String>> tags, String name) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == name && tag.length > 1) {
        return tag[1];
      }
    }
    return null;
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

  static String _placeholders(int count) {
    return List.filled(count, '?').join(',');
  }
}
