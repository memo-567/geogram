/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../services/profile_service.dart';
import '../services/signing_service.dart';
import '../services/storage_config.dart';
import 'remote_chat_browser_page.dart';

/// Page for viewing messages in a chat room from a remote device
class RemoteChatRoomPage extends StatefulWidget {
  final RemoteDevice device;
  final ChatRoom room;

  const RemoteChatRoomPage({
    super.key,
    required this.device,
    required this.room,
  });

  @override
  State<RemoteChatRoomPage> createState() => _RemoteChatRoomPageState();
}

class _RemoteChatRoomPageState extends State<RemoteChatRoomPage> {
  final DevicesService _devicesService = DevicesService();
  final I18nService _i18n = I18nService();
  final ProfileService _profileService = ProfileService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to load from cache first for instant response
      final cachedMessages = await _loadFromCache();
      if (cachedMessages.isNotEmpty) {
        setState(() {
          _messages = cachedMessages;
          _isLoading = false;
        });

        // Scroll to bottom after messages load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        // Silently refresh from API in background
        _refreshFromApi();
        return;
      }

      // No cache - fetch from API
      await _fetchFromApi();
    } catch (e) {
      LogService().log('RemoteChatRoomPage: Error loading messages: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Load messages from cached data on disk
  Future<List<ChatMessage>> _loadFromCache() async {
    try {
      final dataDir = StorageConfig().baseDir;
      final roomPath = '$dataDir/devices/${widget.device.callsign}/chat/${widget.room.id}';
      final roomDir = Directory(roomPath);

      if (!await roomDir.exists()) {
        return [];
      }

      final messages = <ChatMessage>[];
      await for (final entity in roomDir.list()) {
        if (entity is File && entity.path.endsWith('.json') && !entity.path.endsWith('config.json')) {
          try {
            final content = await entity.readAsString();
            final data = json.decode(content) as Map<String, dynamic>;
            messages.add(ChatMessage.fromJson(data));
          } catch (e) {
            LogService().log('Error reading message ${entity.path}: $e');
          }
        }
      }

      // Sort by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      LogService().log('RemoteChatRoomPage: Loaded ${messages.length} cached messages');
      return messages;
    } catch (e) {
      LogService().log('RemoteChatRoomPage: Error loading cache: $e');
      return [];
    }
  }

  /// Fetch fresh messages from API
  Future<void> _fetchFromApi() async {
    try {
      LogService().log('RemoteChatRoomPage: Fetching messages from ${widget.device.callsign}, room ${widget.room.id}');

      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'GET',
        path: '/api/chat/${widget.room.id}/messages?limit=100',
      );

      LogService().log('RemoteChatRoomPage: Response status=${response?.statusCode}, body length=${response?.body.length}');

      if (response != null && response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        LogService().log('RemoteChatRoomPage: Response body type=${responseBody.runtimeType}');

        // Handle both direct list and wrapped response
        final List<dynamic> data = responseBody is List ? responseBody : (responseBody['messages'] ?? []);

        LogService().log('RemoteChatRoomPage: Parsed ${data.length} messages');

        setState(() {
          _messages = data.map((json) => ChatMessage.fromJson(json)).toList();
          _isLoading = false;
        });

        // Scroll to bottom after messages load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        LogService().log('RemoteChatRoomPage: Fetched ${_messages.length} messages from API');
      } else {
        throw Exception('HTTP ${response?.statusCode ?? "null"}: ${response?.body ?? "no response"}');
      }
    } catch (e) {
      LogService().log('RemoteChatRoomPage: ERROR fetching messages: $e');
      throw e;
    }
  }

  /// Silently refresh from API in background
  void _refreshFromApi() {
    _fetchFromApi().catchError((e) {
      LogService().log('RemoteChatRoomPage: Background refresh failed: $e');
      // Don't update UI with error, keep showing cached data
    });
  }

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied to clipboard')),
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final profile = _profileService.getProfile();

      LogService().log('RemoteChatRoomPage: Sending message to ${widget.device.callsign}, room ${widget.room.id}');

      // Use SigningService to create signed event
      final signingService = SigningService();
      await signingService.initialize();

      if (!signingService.canSign(profile)) {
        throw Exception('Cannot send to remote chat: NOSTR keys not configured. Please set up your npub/nsec in Settings.');
      }

      // Generate signed event with room and callsign tags
      // Per chat-format-specification.md: tags must include [['t', 'chat'], ['room', roomId], ['callsign', callsign]]
      final signedEvent = await signingService.generateSignedEvent(
        content,
        {
          'room': widget.room.id,
          'callsign': profile.callsign,
        },
        profile,
      );

      if (signedEvent == null || signedEvent.sig == null) {
        throw Exception('Failed to sign message');
      }

      LogService().log('RemoteChatRoomPage: Created signed event id=${signedEvent.id}');

      // Send as NOSTR-signed event per API specification
      final payload = {'event': signedEvent.toJson()};

      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'POST',
        path: '/api/chat/${widget.room.id}/messages',
        body: jsonEncode(payload),
        headers: {'Content-Type': 'application/json'},
      );

      LogService().log('RemoteChatRoomPage: Response status=${response?.statusCode}');

      if (response != null && (response.statusCode == 200 || response.statusCode == 201)) {
        // Clear input field
        _messageController.clear();

        // Reload messages to show the new one
        await _fetchFromApi();

        // Scroll to bottom
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }

        LogService().log('RemoteChatRoomPage: Message sent successfully');
      } else {
        final errorBody = response?.body ?? 'no response';
        LogService().log('RemoteChatRoomPage: Send failed - status=${response?.statusCode}, body=$errorBody');
        throw Exception('Failed to send message: HTTP ${response?.statusCode}: $errorBody');
      }
    } catch (e) {
      LogService().log('RemoteChatRoomPage: Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.room.name),
            Text(
              widget.device.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
            tooltip: _i18n.t('refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _i18n.t('error_loading_data'),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadMessages,
                              child: Text(_i18n.t('retry')),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_outlined,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No messages',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Be the first to send a message!',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _buildMessageBubble(theme, message);
                            },
                          ),
          ),

          // Message input area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    enabled: !_isSending,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.send,
                          color: theme.colorScheme.primary,
                        ),
                  tooltip: 'Send message',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: () => _copyMessage(message),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author and timestamp header
            Row(
              children: [
                Text(
                  message.author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  message.timestamp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (message.verified) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.verified,
                    size: 14,
                    color: Colors.green,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),

            // Message content
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message.content,
                style: theme.textTheme.bodyMedium,
              ),
            ),

            // Location if available
            if (message.latitude != null && message.longitude != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${message.latitude!.toStringAsFixed(4)}, ${message.longitude!.toStringAsFixed(4)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chat message data model
class ChatMessage {
  final String author;
  final String timestamp;
  final String content;
  final double? latitude;
  final double? longitude;
  final String? npub;
  final String? signature;
  final bool verified;

  ChatMessage({
    required this.author,
    required this.timestamp,
    required this.content,
    this.latitude,
    this.longitude,
    this.npub,
    this.signature,
    required this.verified,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      author: json['author'] as String? ?? 'Unknown',
      timestamp: json['timestamp'] as String? ?? '',
      content: json['content'] as String? ?? '',
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      npub: json['npub'] as String?,
      signature: json['signature'] as String?,
      verified: json['verified'] as bool? ?? false,
    );
  }
}
