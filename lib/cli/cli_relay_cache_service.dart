/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import '../models/relay_chat_room.dart';
import '../models/chat_message.dart';
import 'pure_storage_config.dart';

/// Pure Dart service for caching relay device data locally (CLI version)
/// Creates folders with device callsign for storing collections from each node
class CliRelayCacheService {
  static final CliRelayCacheService _instance = CliRelayCacheService._internal();
  factory CliRelayCacheService() => _instance;
  CliRelayCacheService._internal();

  String? _basePath;
  bool _initialized = false;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final config = PureStorageConfig();
      if (!config.isInitialized) {
        stderr.writeln('CliRelayCacheService: PureStorageConfig not initialized');
        return;
      }

      _basePath = config.devicesDir;

      final devicesDir = Directory(_basePath!);
      if (!await devicesDir.exists()) {
        await devicesDir.create(recursive: true);
      }

      _initialized = true;
      stderr.writeln('CliRelayCacheService initialized at: $_basePath');
    } catch (e) {
      stderr.writeln('Error initializing CliRelayCacheService: $e');
    }
  }

  /// Get the cache directory for a device
  Future<Directory?> getDeviceCacheDir(String deviceCallsign) async {
    if (_basePath == null) return null;

    // Sanitize callsign for use as folder name
    final safeName = deviceCallsign.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = '$_basePath/$safeName';

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// Save chat rooms for a device
  /// [relayUrl] is stored for offline retrieval when the device is unreachable
  Future<void> saveChatRooms(String deviceCallsign, List<RelayChatRoom> rooms, {String? relayUrl}) async {
    if (_basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return;

      final chatDir = Directory('${cacheDir.path}/chat');
      if (!await chatDir.exists()) {
        await chatDir.create(recursive: true);
      }

      // Save rooms list with relay URL for offline use
      final roomsFile = File('${chatDir.path}/rooms.json');
      final data = {
        'updated': DateTime.now().toIso8601String(),
        'device': deviceCallsign,
        'relayUrl': relayUrl ?? (rooms.isNotEmpty ? rooms.first.relayUrl : null),
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

      await roomsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      stderr.writeln('Cached ${rooms.length} chat rooms for $deviceCallsign');
    } catch (e) {
      stderr.writeln('Error saving chat rooms cache: $e');
    }
  }

  /// Load cached chat rooms for a device
  /// If [relayUrl] is empty, uses the stored relayUrl from the cache
  Future<List<RelayChatRoom>> loadChatRooms(String deviceCallsign, String relayUrl) async {
    if (_basePath == null) return [];

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return [];

      final roomsFile = File('${cacheDir.path}/chat/rooms.json');
      if (!await roomsFile.exists()) return [];

      final content = await roomsFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final roomsData = data['rooms'] as List<dynamic>? ?? [];

      // Use stored relayUrl if provided relayUrl is empty
      final effectiveRelayUrl = relayUrl.isNotEmpty
          ? relayUrl
          : (data['relayUrl'] as String? ?? '');

      return roomsData.map((r) {
        return RelayChatRoom.fromJson(
          r as Map<String, dynamic>,
          effectiveRelayUrl,
          deviceCallsign,
        );
      }).toList();
    } catch (e) {
      stderr.writeln('Error loading cached chat rooms: $e');
      return [];
    }
  }

  /// Save messages for a chat room using year folders and daily files
  /// Structure: chat/roomId/2025/2025-11-29_chat.txt
  Future<void> saveMessages(
    String deviceCallsign,
    String roomId,
    List<RelayChatMessage> messages,
  ) async {
    if (_basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return;

      final roomDir = Directory('${cacheDir.path}/chat/$roomId');
      if (!await roomDir.exists()) {
        await roomDir.create(recursive: true);
      }

      // Group messages by date
      final messagesByDate = <String, List<RelayChatMessage>>{};
      for (final msg in messages) {
        final dt = msg.dateTime;
        if (dt == null) continue;

        final dateKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        messagesByDate.putIfAbsent(dateKey, () => []).add(msg);
      }

      // Save each day's messages to separate file
      int totalSaved = 0;
      for (final entry in messagesByDate.entries) {
        final dateStr = entry.key;
        final dayMessages = entry.value;
        final year = dateStr.substring(0, 4);

        // Create year directory with files subfolder
        final yearDir = Directory('${roomDir.path}/$year');
        if (!await yearDir.exists()) {
          await yearDir.create(recursive: true);
          await Directory('${yearDir.path}/files').create();
        }

        // Write daily file
        final dailyFile = File('${yearDir.path}/${dateStr}_chat.txt');
        final buffer = StringBuffer();

        // Header
        buffer.writeln('# ${roomId.toUpperCase()}: $roomId from $dateStr');

        // Messages
        for (final msg in dayMessages) {
          final chatMsg = _relayChatToChatMessage(msg);
          buffer.writeln();
          buffer.write(chatMsg.exportAsText());
        }
        buffer.writeln();

        await dailyFile.writeAsString(buffer.toString());
        totalSaved += dayMessages.length;
      }

      stderr.writeln('Cached $totalSaved messages for room $roomId (${messagesByDate.length} daily files)');
    } catch (e) {
      stderr.writeln('Error saving messages cache: $e');
    }
  }

  /// Save a raw chat file directly (preserves original format with all metadata)
  Future<void> saveRawChatFile(
    String deviceCallsign,
    String roomId,
    String year,
    String filename,
    String content,
  ) async {
    if (_basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return;

      final yearDir = Directory('${cacheDir.path}/chat/$roomId/$year');
      if (!await yearDir.exists()) {
        await yearDir.create(recursive: true);
        // Also create files directory for attachments
        await Directory('${yearDir.path}/files').create();
      }

      final file = File('${yearDir.path}/$filename');
      await file.writeAsString(content);

      stderr.writeln('Cached raw chat file: $deviceCallsign/$roomId/$year/$filename');
    } catch (e) {
      stderr.writeln('Error saving raw chat file: $e');
    }
  }

  /// Check if a chat file exists in cache
  /// If [expectedSize] is provided, returns false if file size doesn't match
  Future<bool> hasCachedChatFile(
    String deviceCallsign,
    String roomId,
    String year,
    String filename, {
    int? expectedSize,
  }) async {
    if (_basePath == null) return false;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return false;

      final file = File('${cacheDir.path}/chat/$roomId/$year/$filename');
      if (!await file.exists()) return false;

      // If expected size provided, compare with actual file size
      if (expectedSize != null) {
        final stat = await file.stat();
        if (stat.size != expectedSize) {
          stderr.writeln('Cache size mismatch for $filename: cached=${stat.size}, expected=$expectedSize');
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get list of cached chat files for a room
  Future<List<Map<String, dynamic>>> getCachedChatFiles(
    String deviceCallsign,
    String roomId,
  ) async {
    if (_basePath == null) return [];

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return [];

      final roomDir = Directory('${cacheDir.path}/chat/$roomId');
      if (!await roomDir.exists()) return [];

      final List<Map<String, dynamic>> files = [];

      await for (final yearEntity in roomDir.list()) {
        if (yearEntity is Directory) {
          final year = yearEntity.path.split('/').last;
          if (RegExp(r'^\d{4}$').hasMatch(year)) {
            await for (final fileEntity in yearEntity.list()) {
              if (fileEntity is File && fileEntity.path.endsWith('_chat.txt')) {
                final filename = fileEntity.path.split('/').last;
                final stat = await fileEntity.stat();
                files.add({
                  'year': year,
                  'filename': filename,
                  'size': stat.size,
                  'modified': stat.modified.millisecondsSinceEpoch,
                });
              }
            }
          }
        }
      }

      // Sort by year and filename
      files.sort((a, b) {
        final yearCompare = (a['year'] as String).compareTo(b['year'] as String);
        if (yearCompare != 0) return yearCompare;
        return (a['filename'] as String).compareTo(b['filename'] as String);
      });

      return files;
    } catch (e) {
      stderr.writeln('Error getting cached chat files: $e');
      return [];
    }
  }

  /// Load cached messages for a chat room from year folders and daily files
  Future<List<RelayChatMessage>> loadMessages(
    String deviceCallsign,
    String roomId,
  ) async {
    if (_basePath == null) return [];

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return [];

      final roomDir = Directory('${cacheDir.path}/chat/$roomId');
      if (!await roomDir.exists()) return [];

      List<RelayChatMessage> allMessages = [];

      // Find all year folders
      final entities = await roomDir.list().toList();
      for (final entity in entities) {
        if (entity is Directory && _isYearFolder(entity.path)) {
          // Find all daily chat files in year folder
          final yearEntities = await entity.list().toList();
          for (final yearEntity in yearEntities) {
            if (yearEntity is File && yearEntity.path.endsWith('_chat.txt')) {
              // Parse messages from daily file
              final content = await yearEntity.readAsString();
              final chatMessages = _parseMessageText(content);
              allMessages.addAll(
                chatMessages.map((msg) => _chatMessageToRelayChat(msg, roomId)),
              );
            }
          }
        }
      }

      // Sort by timestamp
      allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return allMessages;
    } catch (e) {
      stderr.writeln('Error loading cached messages: $e');
      return [];
    }
  }

  /// Check if path is a year folder (4 digits)
  bool _isYearFolder(String folderPath) {
    final name = folderPath.split('/').last;
    return RegExp(r'^\d{4}$').hasMatch(name);
  }

  /// Parse message text content (pure Dart, no Flutter dependencies)
  List<ChatMessage> _parseMessageText(String content) {
    // Split by message start pattern: "> 2" (messages start with year 2xxx)
    final sections = content.split('> 2');
    List<ChatMessage> messages = [];

    // Skip first section (header)
    for (int i = 1; i < sections.length; i++) {
      try {
        final section = '2${sections[i]}'; // Restore the "2" prefix
        final message = _parseMessageSection(section);
        if (message != null) {
          messages.add(message);
        }
      } catch (e) {
        continue; // Skip malformed messages
      }
    }

    return messages;
  }

  /// Parse a single message section
  ChatMessage? _parseMessageSection(String section) {
    final lines = section.split('\n');
    if (lines.isEmpty) return null;

    // Parse header: "2025-11-20 19:10_12 -- CR7BBQ"
    final header = lines[0].trim();
    if (header.length < 23) return null; // Min length check

    final timestamp = header.substring(0, 19).trim(); // YYYY-MM-DD HH:MM_ss
    final author = header.substring(23).trim(); // After " -- "

    if (timestamp.isEmpty || author.isEmpty) return null;

    // Parse content and metadata
    StringBuffer contentBuffer = StringBuffer();
    Map<String, String> metadata = {};
    bool inContent = true;

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];

      if (line.trim().startsWith('--> ')) {
        inContent = false;
        // Parse metadata: "--> key: value"
        final metaLine = line.trim().substring(4); // Remove "--> "
        final colonIndex = metaLine.indexOf(': ');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex);
          final value = metaLine.substring(colonIndex + 2);
          metadata[key] = value;
        }
      } else if (inContent && line.trim().isNotEmpty) {
        // Content line
        if (contentBuffer.isNotEmpty) {
          contentBuffer.writeln();
        }
        contentBuffer.write(line);
      }
    }

    return ChatMessage(
      author: author,
      timestamp: timestamp,
      content: contentBuffer.toString().trim(),
      metadata: metadata,
    );
  }

  /// Convert RelayChatMessage to ChatMessage for export
  ChatMessage _relayChatToChatMessage(RelayChatMessage msg) {
    return ChatMessage(
      author: msg.callsign,
      timestamp: msg.timestamp,
      content: msg.content,
    );
  }

  /// Convert ChatMessage to RelayChatMessage for loading
  /// Extracts NOSTR metadata (npub, signature, created_at) from ChatMessage.metadata
  RelayChatMessage _chatMessageToRelayChat(ChatMessage msg, String roomId) {
    final metadata = msg.metadata;

    // Extract NOSTR fields from metadata
    final npub = metadata['npub'];
    final signature = metadata['signature'];
    final createdAtStr = metadata['created_at'];
    final createdAt = createdAtStr != null ? int.tryParse(createdAtStr) : null;

    // Determine if message has signature and is verified
    final hasSignature = signature != null && signature.isNotEmpty;
    // Messages with valid signature+npub are considered verified when loaded from trusted cache
    final verified = hasSignature && npub != null && npub.isNotEmpty;

    return RelayChatMessage(
      roomId: roomId,
      callsign: msg.author,
      content: msg.content,
      timestamp: msg.timestamp,
      npub: npub,
      signature: signature,
      createdAt: createdAt,
      hasSignature: hasSignature,
      verified: verified,
    );
  }

  /// Get list of cached device callsigns
  Future<List<String>> getCachedDevices() async {
    if (_basePath == null) return [];

    try {
      final devicesDir = Directory(_basePath!);
      if (!await devicesDir.exists()) return [];

      final entities = await devicesDir.list().toList();
      return entities
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .toList();
    } catch (e) {
      stderr.writeln('Error listing cached devices: $e');
      return [];
    }
  }

  /// Check if a device has cached data
  Future<bool> hasCache(String deviceCallsign) async {
    if (_basePath == null) return false;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return false;

      final roomsFile = File('${cacheDir.path}/chat/rooms.json');
      return await roomsFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get cache timestamp for a device
  Future<DateTime?> getCacheTime(String deviceCallsign) async {
    if (_basePath == null) return null;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return null;

      final roomsFile = File('${cacheDir.path}/chat/rooms.json');
      if (!await roomsFile.exists()) return null;

      final content = await roomsFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final updated = data['updated'] as String?;

      if (updated != null) {
        return DateTime.parse(updated);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get cached relay URL for a device
  Future<String?> getCachedRelayUrl(String deviceCallsign) async {
    if (_basePath == null) return null;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return null;

      final roomsFile = File('${cacheDir.path}/chat/rooms.json');
      if (!await roomsFile.exists()) return null;

      final content = await roomsFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data['relayUrl'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Clear cache for a device
  Future<void> clearCache(String deviceCallsign) async {
    if (_basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir != null && await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        stderr.writeln('Cleared cache for $deviceCallsign');
      }
    } catch (e) {
      stderr.writeln('Error clearing cache: $e');
    }
  }

  /// Clear all device caches
  Future<void> clearAllCaches() async {
    if (_basePath == null) return;

    try {
      final devicesDir = Directory(_basePath!);
      if (await devicesDir.exists()) {
        await devicesDir.delete(recursive: true);
        await devicesDir.create(recursive: true);
        stderr.writeln('Cleared all device caches');
      }
    } catch (e) {
      stderr.writeln('Error clearing all caches: $e');
    }
  }
}
