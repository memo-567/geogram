/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../models/relay_chat_room.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import 'log_service.dart';

/// Service for caching device data locally
/// Creates folders with device callsign for storing collections from each node
class RelayCacheService {
  static final RelayCacheService _instance = RelayCacheService._internal();
  factory RelayCacheService() => _instance;
  RelayCacheService._internal();

  String? _basePath;
  bool _initialized = false;

  /// Initialize the cache service
  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      // Web platform doesn't support file-based caching
      LogService().log('RelayCacheService: Web platform, file caching disabled');
      _initialized = true;
      return;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _basePath = '${appDir.path}/geogram/devices';

      final devicesDir = Directory(_basePath!);
      if (!await devicesDir.exists()) {
        await devicesDir.create(recursive: true);
      }

      _initialized = true;
      LogService().log('RelayCacheService initialized at: $_basePath');
    } catch (e) {
      LogService().log('Error initializing RelayCacheService: $e');
    }
  }

  /// Get the cache directory for a device
  Future<Directory?> getDeviceCacheDir(String deviceCallsign) async {
    if (kIsWeb || _basePath == null) return null;

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
  Future<void> saveChatRooms(String deviceCallsign, List<RelayChatRoom> rooms) async {
    if (kIsWeb || _basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return;

      final chatDir = Directory('${cacheDir.path}/chat');
      if (!await chatDir.exists()) {
        await chatDir.create(recursive: true);
      }

      // Save rooms list
      final roomsFile = File('${chatDir.path}/rooms.json');
      final data = {
        'updated': DateTime.now().toIso8601String(),
        'device': deviceCallsign,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

      await roomsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      LogService().log('Cached ${rooms.length} chat rooms for $deviceCallsign');
    } catch (e) {
      LogService().log('Error saving chat rooms cache: $e');
    }
  }

  /// Load cached chat rooms for a device
  Future<List<RelayChatRoom>> loadChatRooms(String deviceCallsign, String relayUrl) async {
    if (kIsWeb || _basePath == null) return [];

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir == null) return [];

      final roomsFile = File('${cacheDir.path}/chat/rooms.json');
      if (!await roomsFile.exists()) return [];

      final content = await roomsFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final roomsData = data['rooms'] as List<dynamic>? ?? [];

      return roomsData.map((r) {
        return RelayChatRoom.fromJson(
          r as Map<String, dynamic>,
          relayUrl,
          deviceCallsign,
        );
      }).toList();
    } catch (e) {
      LogService().log('Error loading cached chat rooms: $e');
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
    if (kIsWeb || _basePath == null) return;

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

      LogService().log('Cached $totalSaved messages for room $roomId (${messagesByDate.length} daily files)');
    } catch (e) {
      LogService().log('Error saving messages cache: $e');
    }
  }

  /// Load cached messages for a chat room from year folders and daily files
  Future<List<RelayChatMessage>> loadMessages(
    String deviceCallsign,
    String roomId,
  ) async {
    if (kIsWeb || _basePath == null) return [];

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
              final chatMessages = ChatService.parseMessageText(content);
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
      LogService().log('Error loading cached messages: $e');
      return [];
    }
  }

  /// Check if path is a year folder (4 digits)
  bool _isYearFolder(String folderPath) {
    final name = folderPath.split('/').last;
    return RegExp(r'^\d{4}$').hasMatch(name);
  }

  /// Convert RelayChatMessage to ChatMessage for export
  ChatMessage _relayChatToChatMessage(RelayChatMessage msg) {
    // RelayChatMessage timestamp is already in chat format: YYYY-MM-DD HH:MM_ss
    return ChatMessage(
      author: msg.callsign,
      timestamp: msg.timestamp,
      content: msg.content,
    );
  }

  /// Convert ChatMessage to RelayChatMessage for loading
  RelayChatMessage _chatMessageToRelayChat(ChatMessage msg, String roomId) {
    return RelayChatMessage(
      roomId: roomId,
      callsign: msg.author,
      content: msg.content,
      timestamp: msg.timestamp,
    );
  }

  /// Get list of cached device callsigns
  Future<List<String>> getCachedDevices() async {
    if (kIsWeb || _basePath == null) return [];

    try {
      final devicesDir = Directory(_basePath!);
      if (!await devicesDir.exists()) return [];

      final entities = await devicesDir.list().toList();
      return entities
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .toList();
    } catch (e) {
      LogService().log('Error listing cached devices: $e');
      return [];
    }
  }

  /// Check if a device has cached data
  Future<bool> hasCache(String deviceCallsign) async {
    if (kIsWeb || _basePath == null) return false;

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
    if (kIsWeb || _basePath == null) return null;

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

  /// Clear cache for a device
  Future<void> clearCache(String deviceCallsign) async {
    if (kIsWeb || _basePath == null) return;

    try {
      final cacheDir = await getDeviceCacheDir(deviceCallsign);
      if (cacheDir != null && await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        LogService().log('Cleared cache for $deviceCallsign');
      }
    } catch (e) {
      LogService().log('Error clearing cache: $e');
    }
  }

  /// Clear all device caches
  Future<void> clearAllCaches() async {
    if (kIsWeb || _basePath == null) return;

    try {
      final devicesDir = Directory(_basePath!);
      if (await devicesDir.exists()) {
        await devicesDir.delete(recursive: true);
        await devicesDir.create(recursive: true);
        LogService().log('Cleared all device caches');
      }
    } catch (e) {
      LogService().log('Error clearing all caches: $e');
    }
  }
}
