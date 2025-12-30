/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../services/profile_service.dart';
import '../services/signing_service.dart';
import '../services/storage_config.dart';
import '../util/nostr_crypto.dart';
import '../util/nostr_event.dart';
import '../util/reaction_utils.dart';
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
  static const Map<String, String> _reactionEmojiMap = {
    'thumbs-up': '👍',
    'heart': '❤️',
    'fire': '🔥',
    'laugh': '😂',
    'celebrate': '🎉',
    'surprise': '😮',
    'sad': '😢',
  };

  final DevicesService _devicesService = DevicesService();
  final I18nService _i18n = I18nService();
  final ProfileService _profileService = ProfileService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  ChatMessage? _quotedMessage;

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

  void _setQuotedMessage(ChatMessage message) {
    setState(() {
      _quotedMessage = message;
    });
  }

  void _clearQuotedMessage() {
    setState(() {
      _quotedMessage = null;
    });
  }

  bool _canDeleteMessage(ChatMessage message) {
    final profile = _profileService.getProfile();
    return message.author.toUpperCase() == profile.callsign.toUpperCase() ||
        (message.npub != null &&
         message.npub!.isNotEmpty &&
         profile.npub.isNotEmpty &&
         message.npub == profile.npub);
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    if (!_canDeleteMessage(message)) return;

    try {
      final profile = _profileService.getProfile();
      final signingService = SigningService();
      await signingService.initialize();

      if (!signingService.canSign(profile)) {
        throw Exception('NOSTR keys not configured');
      }

      final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);
      final event = NostrEvent.textNote(
        pubkeyHex: pubkeyHex,
        content: 'delete',
        tags: [
          ['action', 'delete'],
          ['room', widget.room.id],
          ['timestamp', message.timestamp],
          ['callsign', profile.callsign],
        ],
      );
      event.calculateId();
      final signedEvent = await signingService.signEvent(event, profile);
      if (signedEvent == null) {
        throw Exception('Failed to sign delete request');
      }

      final authEvent = base64Encode(utf8.encode(jsonEncode(signedEvent.toJson())));
      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'DELETE',
        path: '/api/chat/${widget.room.id}/messages/${Uri.encodeComponent(message.timestamp)}',
        headers: {
          'Authorization': 'Nostr $authEvent',
        },
      );

      if (response != null && response.statusCode == 200) {
        await _fetchFromApi();
      } else {
        throw Exception('HTTP ${response?.statusCode ?? "null"}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
      }
    }
  }

  Future<void> _toggleReaction(ChatMessage message, String reaction) async {
    try {
      final profile = _profileService.getProfile();
      final signingService = SigningService();
      await signingService.initialize();

      if (!signingService.canSign(profile)) {
        throw Exception('NOSTR keys not configured');
      }

      final reactionKey = ReactionUtils.normalizeReactionKey(reaction);
      if (reactionKey.isEmpty) {
        throw Exception('Invalid reaction');
      }

      final pubkeyHex = NostrCrypto.decodeNpub(profile.npub);
      final event = NostrEvent.textNote(
        pubkeyHex: pubkeyHex,
        content: 'react',
        tags: [
          ['action', 'react'],
          ['room', widget.room.id],
          ['timestamp', message.timestamp],
          ['reaction', reactionKey],
          ['callsign', profile.callsign],
        ],
      );
      event.calculateId();

      final signedEvent = await signingService.signEvent(event, profile);
      if (signedEvent == null) {
        throw Exception('Failed to sign reaction event');
      }

      final authEvent = base64Encode(utf8.encode(jsonEncode(signedEvent.toJson())));
      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'POST',
        path: '/api/chat/${widget.room.id}/messages/${Uri.encodeComponent(message.timestamp)}/reactions',
        headers: {
          'Authorization': 'Nostr $authEvent',
        },
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawReactions = data['reactions'] as Map?;
        final reactions = <String, List<String>>{};
        if (rawReactions != null) {
          rawReactions.forEach((key, value) {
            if (value is List) {
              reactions[key.toString()] =
                  value.map((entry) => entry.toString()).toList();
            }
          });
        }
        final normalized = ReactionUtils.normalizeReactionMap(reactions);

        if (mounted) {
          setState(() {
            final index = _messages.indexWhere((msg) =>
                msg.timestamp == message.timestamp &&
                msg.author == message.author);
            if (index != -1) {
              _messages[index] = message.copyWith(reactions: normalized);
            }
          });
        }
      } else {
        throw Exception('HTTP ${response?.statusCode ?? "null"}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to react: $e')),
        );
      }
    }
  }

  bool _isDesktopPlatform() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  void _showMessageOptions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Wrap(
                spacing: 12,
                children: _reactionEmojiMap.entries.map((entry) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleReaction(message, entry.key);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Quote'),
              onTap: () {
                Navigator.pop(context);
                _setQuotedMessage(message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(message);
              },
            ),
            if (_canDeleteMessage(message))
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete message',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
          ],
        ),
      ),
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

      final metadata = <String, String>{};
      if (_quotedMessage != null) {
        metadata['quote'] = _quotedMessage!.timestamp;
        metadata['quote_author'] = _quotedMessage!.author;
        if (_quotedMessage!.content.isNotEmpty) {
          final excerpt = _quotedMessage!.content.length > 120
              ? _quotedMessage!.content.substring(0, 120)
              : _quotedMessage!.content;
          metadata['quote_excerpt'] = excerpt;
        }
      }

      // Send as NOSTR-signed event per API specification
      final payload = {
        'event': signedEvent.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

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
        _clearQuotedMessage();

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_quotedMessage != null) _buildReplyPreview(theme),
                Row(
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
        onLongPress: () => _showMessageOptions(message),
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
                if (_isDesktopPlatform()) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    tooltip: 'Message options',
                    onPressed: () => _showMessageOptions(message),
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isQuote) _buildQuotePreview(theme, message),
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),

            if (message.reactions.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildReactionsRow(theme, message),
            ],

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

  Widget _buildReactionsRow(ThemeData theme, ChatMessage message) {
    final currentCallsign = _profileService.getProfile().callsign.toUpperCase();
    final normalized = ReactionUtils.normalizeReactionMap(message.reactions);
    final entries = normalized.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final chips = <Widget>[];

    for (final entry in entries) {
      final reactionKey = entry.key;
      final users = entry.value;
      if (users.isEmpty) continue;
      final reacted = users.any((u) => u.toUpperCase() == currentCallsign);
      final label = '${_reactionLabel(reactionKey)} ${users.length}';

      chips.add(
        InkWell(
          onTap: () => _toggleReaction(message, reactionKey),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: reacted
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: reacted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: reacted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips,
    );
  }

  String _reactionLabel(String reactionKey) {
    final normalizedKey = ReactionUtils.normalizeReactionKey(reactionKey);
    final emoji = _reactionEmojiMap[normalizedKey];
    if (emoji != null) {
      return emoji;
    }
    return normalizedKey;
  }

  Widget _buildQuotePreview(ThemeData theme, ChatMessage message) {
    final author = message.quotedAuthor ?? 'Unknown';
    final excerpt = message.quotedExcerpt ?? '';
    final display = excerpt.isNotEmpty ? excerpt : 'Quoted message';
    final truncated = display.length > 120 ? '${display.substring(0, 120)}...' : display;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            truncated,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    final quoted = _quotedMessage!;
    final excerpt = quoted.content.isNotEmpty ? quoted.content : 'Quoted message';
    final truncated = excerpt.length > 120 ? '${excerpt.substring(0, 120)}...' : excerpt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quoted.author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  truncated,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearQuotedMessage,
            tooltip: 'Remove quote',
          ),
        ],
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
  final Map<String, String> metadata;
  final Map<String, List<String>> reactions;

  ChatMessage({
    required this.author,
    required this.timestamp,
    required this.content,
    this.latitude,
    this.longitude,
    this.npub,
    this.signature,
    required this.verified,
    Map<String, String>? metadata,
    Map<String, List<String>>? reactions,
  })  : metadata = metadata ?? {},
        reactions = reactions ?? {};

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'] as Map?;
    final metadata = rawMetadata != null
        ? rawMetadata.map((key, value) => MapEntry(key.toString(), value.toString()))
        : <String, String>{};
    final rawReactions = json['reactions'] as Map?;
    final reactions = <String, List<String>>{};
    if (rawReactions != null) {
      rawReactions.forEach((key, value) {
        if (value is List) {
          reactions[key.toString()] =
              value.map((entry) => entry.toString()).toList();
        }
      });
    }
    return ChatMessage(
      author: json['author'] as String? ?? 'Unknown',
      timestamp: json['timestamp'] as String? ?? '',
      content: json['content'] as String? ?? '',
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      npub: (json['npub'] as String?) ?? metadata['npub'],
      signature: (json['signature'] as String?) ?? metadata['signature'],
      verified: json['verified'] as bool? ?? false,
      metadata: metadata,
      reactions: ReactionUtils.normalizeReactionMap(reactions),
    );
  }

  ChatMessage copyWith({
    String? author,
    String? timestamp,
    String? content,
    double? latitude,
    double? longitude,
    String? npub,
    String? signature,
    bool? verified,
    Map<String, String>? metadata,
    Map<String, List<String>>? reactions,
  }) {
    return ChatMessage(
      author: author ?? this.author,
      timestamp: timestamp ?? this.timestamp,
      content: content ?? this.content,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      npub: npub ?? this.npub,
      signature: signature ?? this.signature,
      verified: verified ?? this.verified,
      metadata: metadata ?? Map<String, String>.from(this.metadata),
      reactions: reactions ?? Map<String, List<String>>.from(this.reactions),
    );
  }

  bool get isQuote =>
      metadata.containsKey('quote') ||
      metadata.containsKey('quote_author') ||
      metadata.containsKey('quote_excerpt');

  String? get quotedAuthor => metadata['quote_author'];

  String? get quotedExcerpt => metadata['quote_excerpt'];
}
