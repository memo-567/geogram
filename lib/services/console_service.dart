/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Service for managing console terminal sessions.
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'dart:math';
import '../models/console_session.dart';
import 'log_service.dart';
import 'profile_service.dart';

/// Service for managing console sessions
class ConsoleService {
  static final ConsoleService _instance = ConsoleService._internal();
  factory ConsoleService() => _instance;
  ConsoleService._internal();

  String? _collectionPath;
  final List<ConsoleSession> _sessions = [];
  final _random = Random();

  /// Get collection path
  String? get collectionPath => _collectionPath;

  /// Get all sessions
  List<ConsoleSession> get sessions => List.unmodifiable(_sessions);

  /// Get sessions that should keep running
  List<ConsoleSession> get keepRunningSessions =>
      _sessions.where((s) => s.keepRunning).toList();

  /// Initialize the service with a collection path
  Future<void> initializeCollection(String collectionPath) async {
    _collectionPath = collectionPath;
    _sessions.clear();

    final sessionsDir = Directory('$collectionPath/sessions');
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }

    // Load existing sessions
    await _loadSessions();
  }

  /// Load all sessions from the collection
  Future<void> _loadSessions() async {
    if (_collectionPath == null) return;

    final sessionsDir = Directory('$_collectionPath/sessions');
    if (!await sessionsDir.exists()) return;

    final entities = await sessionsDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        final session = await _loadSessionFromFolder(entity.path);
        if (session != null) {
          _sessions.add(session);
        }
      }
    }

    // Sort by created date (newest first)
    _sessions.sort((a, b) => b.createdDateTime.compareTo(a.createdDateTime));
  }

  /// Load a single session from its folder
  Future<ConsoleSession?> _loadSessionFromFolder(String folderPath) async {
    final sessionFile = File('$folderPath/session.txt');
    if (!await sessionFile.exists()) return null;

    try {
      final content = await sessionFile.readAsString();
      final session = _parseSessionContent(content, folderPath);

      // Load mounts if available
      if (session != null) {
        final mountsFile = File('$folderPath/mounts.json');
        if (await mountsFile.exists()) {
          final mountsContent = await mountsFile.readAsString();
          final mountsJson = jsonDecode(mountsContent) as Map<String, dynamic>;
          final mounts =
              (mountsJson['mounts'] as List<dynamic>?)
                  ?.map((m) => ConsoleMount.fromJson(m as Map<String, dynamic>))
                  .toList() ??
              [];
          return session.copyWith(mounts: mounts);
        }
      }

      return session;
    } catch (e) {
      LogService().log('Error loading session from $folderPath: $e');
      return null;
    }
  }

  /// Parse session.txt content into a ConsoleSession model
  ConsoleSession? _parseSessionContent(String content, String folderPath) {
    final lines = content.split('\n');
    if (lines.isEmpty) return null;

    String? name;
    String? created;
    String? author;
    String vmType = 'alpine-x86';
    int memory = 128;
    bool networkEnabled = true;
    bool keepRunning = false;
    ConsoleSessionState state = ConsoleSessionState.stopped;
    String? metadataNpub;
    String? signature;
    final descriptionLines = <String>[];

    bool inDescription = false;
    bool headerEnded = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // Parse title
      if (trimmed.startsWith('# SESSION:')) {
        name = trimmed.substring('# SESSION:'.length).trim();
        continue;
      }

      // Parse metadata at end
      if (trimmed.startsWith('--> npub:')) {
        metadataNpub = trimmed.substring('--> npub:'.length).trim();
        inDescription = false;
        continue;
      }
      if (trimmed.startsWith('--> signature:')) {
        signature = trimmed.substring('--> signature:'.length).trim();
        inDescription = false;
        continue;
      }

      // Parse header fields
      if (!headerEnded) {
        if (trimmed.startsWith('CREATED:')) {
          created = trimmed.substring('CREATED:'.length).trim();
          continue;
        }
        if (trimmed.startsWith('AUTHOR:')) {
          author = trimmed.substring('AUTHOR:'.length).trim();
          continue;
        }
        if (trimmed.startsWith('VM_TYPE:')) {
          vmType = trimmed.substring('VM_TYPE:'.length).trim();
          continue;
        }
        if (trimmed.startsWith('MEMORY:')) {
          memory =
              int.tryParse(trimmed.substring('MEMORY:'.length).trim()) ?? 128;
          continue;
        }
        if (trimmed.startsWith('NETWORK:')) {
          networkEnabled =
              trimmed.substring('NETWORK:'.length).trim().toLowerCase() ==
              'enabled';
          continue;
        }
        if (trimmed.startsWith('KEEP_RUNNING:')) {
          keepRunning =
              trimmed.substring('KEEP_RUNNING:'.length).trim().toLowerCase() ==
              'true';
          continue;
        }
        if (trimmed.startsWith('STATUS:')) {
          state = ConsoleSession.parseState(
            trimmed.substring('STATUS:'.length).trim(),
          );
          continue;
        }

        // Empty line after header starts description
        if (trimmed.isEmpty && created != null) {
          headerEnded = true;
          inDescription = true;
          continue;
        }
      } else if (inDescription) {
        // Collect description lines
        if (!trimmed.startsWith('-->')) {
          descriptionLines.add(line);
        }
      }
    }

    if (name == null || created == null || author == null) {
      return null;
    }

    // Extract session ID from folder name
    final id = folderPath.split('/').last;

    return ConsoleSession(
      id: id,
      name: name,
      created: created,
      author: author,
      vmType: vmType,
      memory: memory,
      networkEnabled: networkEnabled,
      keepRunning: keepRunning,
      state: state,
      description: descriptionLines.join('\n').trim(),
      metadataNpub: metadataNpub,
      signature: signature,
      sessionPath: folderPath,
      collectionPath: _collectionPath,
    );
  }

  /// Generate a unique session ID (8 alphanumeric characters)
  String _generateSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  /// Create a new session
  Future<ConsoleSession> createSession({
    required String name,
    String? description,
  }) async {
    if (_collectionPath == null) {
      throw Exception('ConsoleService not initialized');
    }

    final id = _generateSessionId();
    final now = DateTime.now();
    final created =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

    final author = ProfileService().getProfile().callsign;

    final sessionPath = '$_collectionPath/sessions/$id';
    final savedPath = '$sessionPath/saved';

    // Create directories
    await Directory(sessionPath).create(recursive: true);
    await Directory(savedPath).create(recursive: true);

    final session = ConsoleSession(
      id: id,
      name: name,
      created: created,
      author: author,
      state: ConsoleSessionState.stopped,
      description: description,
      sessionPath: sessionPath,
      collectionPath: _collectionPath,
    );

    // Save session.txt
    await _saveSessionFile(session);

    // Save mounts.json
    await _saveMountsFile(session);

    _sessions.insert(0, session);
    return session;
  }

  /// Update an existing session
  Future<void> updateSession(ConsoleSession session) async {
    await _saveSessionFile(session);
    await _saveMountsFile(session);

    // Update in memory
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      _sessions[index] = session;
    }
  }

  /// Save session.txt file
  Future<void> _saveSessionFile(ConsoleSession session) async {
    if (session.sessionPath == null) return;

    final file = File('${session.sessionPath}/session.txt');
    await file.writeAsString(session.toSessionTxt());
  }

  /// Save mounts.json file
  Future<void> _saveMountsFile(ConsoleSession session) async {
    if (session.sessionPath == null) return;

    final file = File('${session.sessionPath}/mounts.json');
    final json = jsonEncode(session.mountsToJson());
    await file.writeAsString(json);
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    final session = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw Exception('Session not found'),
    );

    if (session.sessionPath != null) {
      final dir = Directory(session.sessionPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    _sessions.removeWhere((s) => s.id == sessionId);
  }

  /// Get a session by ID
  ConsoleSession? getSession(String sessionId) {
    try {
      return _sessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  /// Update session state
  Future<void> updateSessionState(
    String sessionId,
    ConsoleSessionState state,
  ) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final updated = session.copyWith(state: state);
    await updateSession(updated);
  }

  /// List saved state files for a session
  Future<List<String>> listSavedStates(String sessionId) async {
    final session = getSession(sessionId);
    if (session?.savedStatesPath == null) return [];

    final dir = Directory(session!.savedStatesPath!);
    if (!await dir.exists()) return [];

    final states = <String>[];
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.state')) {
        states.add(entity.path.split('/').last.replaceAll('.state', ''));
      }
    }

    // Sort by date (newest first)
    states.sort((a, b) => b.compareTo(a));
    return states;
  }

  /// Check if current state exists
  Future<bool> hasCurrentState(String sessionId) async {
    final session = getSession(sessionId);
    if (session?.currentStatePath == null) return false;

    return await File(session!.currentStatePath!).exists();
  }

  /// Add a mount point to a session
  Future<void> addMount(String sessionId, ConsoleMount mount) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final mounts = List<ConsoleMount>.from(session.mounts)..add(mount);
    await updateSession(session.copyWith(mounts: mounts));
  }

  /// Remove a mount point from a session
  Future<void> removeMount(String sessionId, String vmPath) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final mounts = session.mounts.where((m) => m.vmPath != vmPath).toList();
    await updateSession(session.copyWith(mounts: mounts));
  }

  /// Update a mount point
  Future<void> updateMount(String sessionId, ConsoleMount mount) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final mounts = session.mounts.map((m) {
      if (m.vmPath == mount.vmPath) return mount;
      return m;
    }).toList();
    await updateSession(session.copyWith(mounts: mounts));
  }

  /// Refresh sessions list
  Future<void> refresh() async {
    if (_collectionPath == null) return;
    _sessions.clear();
    await _loadSessions();
  }

  /// Dispose resources
  void dispose() {
    _sessions.clear();
    _collectionPath = null;
  }
}
