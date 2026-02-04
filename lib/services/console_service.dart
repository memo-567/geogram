/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Service for managing console terminal sessions.
 */

import 'dart:convert';
import 'dart:math';
import '../models/console_session.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'profile_storage.dart';

/// Service for managing console sessions
class ConsoleService {
  static final ConsoleService _instance = ConsoleService._internal();
  factory ConsoleService() => _instance;
  ConsoleService._internal();

  /// Profile storage for file operations (encrypted or filesystem)
  /// IMPORTANT: This MUST be set before using the service.
  late ProfileStorage _storage;

  String? _appPath;
  final List<ConsoleSession> _sessions = [];
  final _random = Random();

  /// Whether using encrypted storage
  bool get useEncryptedStorage => _storage.isEncrypted;

  /// Set the profile storage for file operations
  /// MUST be called before initializeApp
  void setStorage(ProfileStorage storage) {
    _storage = storage;
  }

  /// Get collection path
  String? get appPath => _appPath;

  /// Get all sessions
  List<ConsoleSession> get sessions => List.unmodifiable(_sessions);

  /// Get sessions that should keep running
  List<ConsoleSession> get keepRunningSessions =>
      _sessions.where((s) => s.keepRunning).toList();

  /// Initialize the service with a collection path
  Future<void> initializeApp(String appPath) async {
    _appPath = appPath;
    _sessions.clear();

    // Create sessions directory using storage
    await _storage.createDirectory('sessions');

    // Load existing sessions
    await _loadSessions();
  }

  /// Load all sessions from the collection
  Future<void> _loadSessions() async {
    if (_appPath == null) return;

    final entries = await _storage.listDirectory('sessions');
    for (final entry in entries) {
      if (entry.isDirectory) {
        final session = await _loadSessionFromStorage(entry.path);
        if (session != null) {
          _sessions.add(session);
        }
      }
    }

    // Sort by created date (newest first)
    _sessions.sort((a, b) => b.createdDateTime.compareTo(a.createdDateTime));
  }

  /// Load a single session from storage using relative path
  Future<ConsoleSession?> _loadSessionFromStorage(String relativePath) async {
    final sessionPath = '$relativePath/session.txt';
    final content = await _storage.readString(sessionPath);
    if (content == null) return null;

    try {
      final fullPath = _storage.getAbsolutePath(relativePath);
      final session = _parseSessionContent(content, fullPath);

      // Load mounts if available
      if (session != null) {
        final mountsPath = '$relativePath/mounts.json';
        final mountsContent = await _storage.readString(mountsPath);
        if (mountsContent != null) {
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
      LogService().log('Error loading session from $relativePath: $e');
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
      appPath: _appPath,
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
    if (_appPath == null) {
      throw Exception('ConsoleService not initialized');
    }

    final id = _generateSessionId();
    final now = DateTime.now();
    final created =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

    final author = ProfileService().getProfile().callsign;

    final sessionRelativePath = 'sessions/$id';
    final savedRelativePath = '$sessionRelativePath/saved';
    final sessionPath = _storage.getAbsolutePath(sessionRelativePath);

    // Create directories using storage
    await _storage.createDirectory(sessionRelativePath);
    await _storage.createDirectory(savedRelativePath);

    final session = ConsoleSession(
      id: id,
      name: name,
      created: created,
      author: author,
      state: ConsoleSessionState.stopped,
      description: description,
      sessionPath: sessionPath,
      appPath: _appPath,
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

    final relativePath = 'sessions/${session.id}/session.txt';
    await _storage.writeString(relativePath, session.toSessionTxt());
  }

  /// Save mounts.json file
  Future<void> _saveMountsFile(ConsoleSession session) async {
    if (session.sessionPath == null) return;

    final relativePath = 'sessions/${session.id}/mounts.json';
    final json = jsonEncode(session.mountsToJson());
    await _storage.writeString(relativePath, json);
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    // Verify session exists in memory
    if (!_sessions.any((s) => s.id == sessionId)) {
      throw Exception('Session not found');
    }

    final relativePath = 'sessions/$sessionId';
    if (await _storage.exists(relativePath)) {
      await _storage.deleteDirectory(relativePath, recursive: true);
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
    if (session == null) return [];

    final relativePath = 'sessions/$sessionId/saved';
    if (!await _storage.exists(relativePath)) return [];

    final states = <String>[];
    final entries = await _storage.listDirectory(relativePath);
    for (final entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.state')) {
        states.add(entry.name.replaceAll('.state', ''));
      }
    }

    // Sort by date (newest first)
    states.sort((a, b) => b.compareTo(a));
    return states;
  }

  /// Check if current state exists
  Future<bool> hasCurrentState(String sessionId) async {
    final session = getSession(sessionId);
    if (session == null) return false;

    final relativePath = 'sessions/$sessionId/current.state';
    return await _storage.exists(relativePath);
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
    if (_appPath == null) return;
    _sessions.clear();
    await _loadSessions();
  }

  /// Dispose resources
  void dispose() {
    _sessions.clear();
    _appPath = null;
  }
}
