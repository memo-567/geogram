/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/collection.dart';
import '../models/chat_channel.dart';
import '../models/chat_message.dart';
import '../models/chat_settings.dart';
import '../models/relay_chat_room.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import '../services/relay_service.dart';
import '../services/relay_cache_service.dart';
import '../widgets/channel_list_widget.dart';
import '../widgets/message_list_widget.dart';
import '../widgets/message_input_widget.dart';
import '../widgets/new_channel_dialog.dart';
import 'chat_settings_page.dart';

/// Page for browsing and interacting with a chat collection
class ChatBrowserPage extends StatefulWidget {
  final Collection collection;

  const ChatBrowserPage({
    Key? key,
    required this.collection,
  }) : super(key: key);

  @override
  State<ChatBrowserPage> createState() => _ChatBrowserPageState();
}

class _ChatBrowserPageState extends State<ChatBrowserPage> {
  final ChatService _chatService = ChatService();
  final ProfileService _profileService = ProfileService();
  final RelayService _relayService = RelayService();
  final RelayCacheService _cacheService = RelayCacheService();

  List<ChatChannel> _channels = [];
  ChatChannel? _selectedChannel;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;

  // Relay chat rooms
  List<RelayChatRoom> _relayRooms = [];
  RelayChatRoom? _selectedRelayRoom;
  List<RelayChatMessage> _relayMessages = [];
  bool _loadingRelayRooms = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  /// Initialize chat service and load data
  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Initialize chat service with collection path
      final storagePath = widget.collection.storagePath;
      if (storagePath == null) {
        throw Exception('Collection storage path is null');
      }

      // Pass current user's npub to initialize admin if needed
      final currentProfile = _profileService.getProfile();
      await _chatService.initializeCollection(
        storagePath,
        creatorNpub: currentProfile.npub,
      );

      // Load channels
      _channels = _chatService.channels;

      // Select main channel by default only in wide screen mode
      if (_channels.isNotEmpty && mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideScreen = screenWidth >= 600;

        if (isWideScreen) {
          await _selectChannel(_channels.first);
        }
      }

      setState(() {
        _isInitialized = true;
      });

      // Load relay chat rooms if connected
      _loadRelayRooms();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize chat: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load relay chat rooms from connected relay
  Future<void> _loadRelayRooms() async {
    final relay = _relayService.getConnectedRelay();
    if (relay == null) return;

    setState(() {
      _loadingRelayRooms = true;
    });

    try {
      // Initialize cache service
      await _cacheService.initialize();

      // Fetch rooms from relay
      final rooms = await _relayService.fetchChatRooms(relay.url);

      if (rooms.isNotEmpty) {
        // Cache the rooms using the relay's callsign (from API response)
        final relayCallsign = rooms.first.relayName;
        if (relayCallsign.isNotEmpty) {
          await _cacheService.saveChatRooms(relayCallsign, rooms);
        }
      }

      setState(() {
        _relayRooms = rooms;
      });
    } catch (e) {
      // Try loading from cache using relay's callsign
      final relay = _relayService.getConnectedRelay();
      if (relay != null) {
        // Use callsign if available, fallback to name
        final cacheKey = relay.callsign ?? relay.name;
        if (cacheKey.isNotEmpty) {
          final cachedRooms = await _cacheService.loadChatRooms(cacheKey, relay.url);
          setState(() {
            _relayRooms = cachedRooms;
          });
        }
      }
    } finally {
      setState(() {
        _loadingRelayRooms = false;
      });
    }
  }

  /// Select a channel and load its messages
  Future<void> _selectChannel(ChatChannel channel) async {
    setState(() {
      _selectedChannel = channel;
      _selectedRelayRoom = null; // Deselect relay room
      _isLoading = true;
    });

    try {
      // Load messages for selected channel
      final messages = await _chatService.loadMessages(
        channel.id,
        limit: 100,
      );

      setState(() {
        _messages = messages;
      });
    } catch (e) {
      _showError('Failed to load messages: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Select a channel for mobile view (just sets it, layout handles display)
  Future<void> _selectChannelMobile(ChatChannel channel) async {
    await _selectChannel(channel);
  }

  /// Select a relay room and load its messages
  Future<void> _selectRelayRoom(RelayChatRoom room) async {
    setState(() {
      _selectedRelayRoom = room;
      _selectedChannel = null; // Deselect local channel
      _isLoading = true;
    });

    try {
      // Fetch messages from relay
      final messages = await _relayService.fetchRoomMessages(
        room.relayUrl,
        room.id,
        limit: 100,
      );

      // Cache messages
      if (room.relayName.isNotEmpty) {
        await _cacheService.saveMessages(room.relayName, room.id, messages);
      }

      setState(() {
        _relayMessages = messages;
      });
    } catch (e) {
      // Try loading from cache
      if (room.relayName.isNotEmpty) {
        final cachedMessages = await _cacheService.loadMessages(
          room.relayName,
          room.id,
        );
        setState(() {
          _relayMessages = cachedMessages;
        });
      }
      _showError('Failed to load relay messages: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Convert relay messages to ChatMessage format for display
  List<ChatMessage> _convertRelayMessages(List<RelayChatMessage> relayMessages) {
    return relayMessages.map((rm) {
      return ChatMessage(
        author: rm.callsign,
        timestamp: rm.timestamp,
        content: rm.content,
      );
    }).toList();
  }

  /// Send a message
  Future<void> _sendMessage(String content, String? filePath) async {
    final currentProfile = _profileService.getProfile();
    if (currentProfile.callsign.isEmpty) {
      _showError('No active callsign. Please set up your profile first.');
      return;
    }

    // Handle relay room message
    if (_selectedRelayRoom != null) {
      await _sendRelayMessage(content);
      return;
    }

    if (_selectedChannel == null) return;

    try {
      // Load chat settings
      final settings = await _loadChatSettings();

      // Create message
      Map<String, String> metadata = {};

      // Handle file attachment
      String? attachedFileName;
      if (filePath != null) {
        attachedFileName = await _copyFileToChannel(filePath);
        if (attachedFileName != null) {
          metadata['file'] = attachedFileName;
        }
      }

      // Add signing if enabled
      if (settings.signMessages &&
          currentProfile.npub.isNotEmpty &&
          currentProfile.nsec.isNotEmpty) {
        // Add npub
        metadata['npub'] = currentProfile.npub;

        // TODO: Implement proper NOSTR signing using secp256k1
        // For now, add a placeholder signature
        // Real implementation should:
        // 1. Construct message text to sign (everything before signature)
        // 2. Hash the message using SHA-256
        // 3. Sign the hash with nsec using Schnorr signature on secp256k1
        // 4. Encode signature as hex
        metadata['signature'] = _generatePlaceholderSignature(
          content,
          metadata,
          currentProfile.nsec,
        );
      }

      // Create message object
      final message = ChatMessage.now(
        author: currentProfile.callsign,
        content: content,
        metadata: metadata.isNotEmpty ? metadata : null,
      );

      // Save message
      await _chatService.saveMessage(_selectedChannel!.id, message);

      // Add to local list (optimistic update)
      setState(() {
        _messages.add(message);
      });
    } catch (e) {
      _showError('Failed to send message: $e');
    }
  }

  /// Send a message to a relay chat room
  Future<void> _sendRelayMessage(String content) async {
    if (_selectedRelayRoom == null) return;

    final currentProfile = _profileService.getProfile();

    try {
      final success = await _relayService.postRoomMessage(
        _selectedRelayRoom!.relayUrl,
        _selectedRelayRoom!.id,
        currentProfile.callsign,
        content,
      );

      if (success) {
        // Add optimistic update
        final now = DateTime.now();
        final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

        final newMessage = RelayChatMessage(
          timestamp: timestamp,
          callsign: currentProfile.callsign,
          content: content,
          roomId: _selectedRelayRoom!.id,
        );

        setState(() {
          _relayMessages.add(newMessage);
        });
      } else {
        _showError('Failed to send message to relay');
      }
    } catch (e) {
      _showError('Failed to send relay message: $e');
    }
  }

  /// Load chat settings
  Future<ChatSettings> _loadChatSettings() async {
    try {
      final storagePath = widget.collection.storagePath;
      if (storagePath == null) return ChatSettings();

      final settingsFile =
          File(path.join(storagePath, 'extra', 'settings.json'));
      if (!await settingsFile.exists()) {
        return ChatSettings();
      }

      final content = await settingsFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ChatSettings.fromJson(json);
    } catch (e) {
      return ChatSettings();
    }
  }

  /// Generate placeholder signature
  /// TODO: Replace with proper NOSTR signing implementation
  String _generatePlaceholderSignature(
    String content,
    Map<String, String> metadata,
    String nsec,
  ) {
    // This is a placeholder. Real implementation needs:
    // - secp256k1 library for Schnorr signatures
    // - Proper message hashing (SHA-256)
    // - Signature encoding
    return 'PLACEHOLDER_SIGNATURE_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Copy file to channel's files folder
  Future<String?> _copyFileToChannel(String sourceFilePath) async {
    try {
      final sourceFile = File(sourceFilePath);
      if (!await sourceFile.exists()) {
        _showError('File not found');
        return null;
      }

      // Determine destination folder
      final storagePath = widget.collection.storagePath;
      if (storagePath == null) {
        _showError('Collection storage path is null');
        return null;
      }

      // For main channel, use year subfolder; for others, use channel folder directly
      String filesPath;
      if (_selectedChannel!.id == 'main') {
        final year = DateTime.now().year.toString();
        filesPath = path.join(storagePath, _selectedChannel!.folder, year, 'files');
      } else {
        filesPath = path.join(storagePath, _selectedChannel!.folder, 'files');
      }

      final filesDir = Directory(filesPath);

      // Create files directory if it doesn't exist
      if (!await filesDir.exists()) {
        await filesDir.create(recursive: true);
      }

      // Truncate filename if longer than 100 chars
      String fileName = path.basename(sourceFilePath);
      if (fileName.length > 100) {
        final ext = path.extension(fileName);
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final maxNameLength = 100 - ext.length;
        fileName = nameWithoutExt.substring(0, maxNameLength) + ext;
      }

      final destPath = path.join(filesDir.path, fileName);
      var destFile = File(destPath);

      // Handle duplicate filenames
      int counter = 1;
      while (await destFile.exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        final newName = '${nameWithoutExt}_$counter$ext';
        destFile = File(path.join(filesDir.path, newName));
        counter++;
      }

      // Copy file
      await sourceFile.copy(destFile.path);

      return path.basename(destFile.path);
    } catch (e) {
      _showError('Failed to copy file: $e');
      return null;
    }
  }

  /// Check if user can delete a message
  bool _canDeleteMessage(ChatMessage message) {
    if (_selectedChannel == null) return false;

    final currentProfile = _profileService.getProfile();
    final userNpub = currentProfile.npub;

    // Check if user is admin or moderator
    return _chatService.security.canModerate(userNpub, _selectedChannel!.id);
  }

  /// Delete a message
  Future<void> _deleteMessage(ChatMessage message) async {
    if (_selectedChannel == null) return;

    try {
      final currentProfile = _profileService.getProfile();
      final userNpub = currentProfile.npub;

      await _chatService.deleteMessage(
        _selectedChannel!.id,
        message,
        userNpub,
      );

      // Remove from local list
      setState(() {
        _messages.removeWhere((msg) =>
            msg.timestamp == message.timestamp && msg.author == message.author);
      });

      _showSuccess('Message deleted');
    } catch (e) {
      _showError('Failed to delete message: $e');
    }
  }

  /// Open attached file
  Future<void> _openAttachedFile(ChatMessage message) async {
    if (!message.hasFile) return;

    try {
      final storagePath = widget.collection.storagePath;
      if (storagePath == null) {
        _showError('Collection storage path is null');
        return;
      }

      // Construct file path based on channel type
      String filePath;
      if (_selectedChannel!.id == 'main') {
        // For main channel, files are in year folders
        final year = message.dateTime.year.toString();
        filePath = path.join(
          storagePath,
          _selectedChannel!.folder,
          year,
          'files',
          message.attachedFile!,
        );
      } else {
        // For DM and group channels, files are in channel folder
        filePath = path.join(
          storagePath,
          _selectedChannel!.folder,
          'files',
          message.attachedFile!,
        );
      }

      final file = File(filePath);
      if (!await file.exists()) {
        _showError('File not found: ${message.attachedFile}');
        return;
      }

      // Open file with default application (using xdg-open on Linux)
      if (Platform.isLinux) {
        await Process.run('xdg-open', [filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else if (Platform.isWindows) {
        await Process.run('start', [filePath], runInShell: true);
      }
    } catch (e) {
      _showError('Failed to open file: $e');
    }
  }

  /// Show new channel dialog
  Future<void> _showNewChannelDialog() async {
    final result = await showDialog<ChatChannel>(
      context: context,
      builder: (context) => NewChannelDialog(
        existingChannelIds: _channels.map((ch) => ch.id).toList(),
        knownCallsigns: _chatService.participants.keys.toList(),
      ),
    );

    if (result != null) {
      try {
        setState(() {
          _isLoading = true;
        });

        // Create channel
        final channel = await _chatService.createChannel(result);

        // Refresh channels
        await _chatService.refreshChannels();

        setState(() {
          _channels = _chatService.channels;
        });

        // Select the new channel
        await _selectChannel(channel);

        _showSuccess('Channel created successfully');
      } catch (e) {
        _showError('Failed to create channel: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Refresh current channel
  Future<void> _refreshChannel() async {
    if (_selectedChannel != null) {
      await _selectChannel(_selectedChannel!);
    }
  }

  /// Open settings page
  void _openSettings() {
    final storagePath = widget.collection.storagePath;
    if (storagePath == null) {
      _showError('Collection storage path is null');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatSettingsPage(
          collectionPath: storagePath,
        ),
      ),
    ).then((_) {
      // Reload security settings when returning
      _chatService.refreshChannels();
      setState(() {});
    });
  }

  /// Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Show success message
  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 600;

    return Scaffold(
      appBar: AppBar(
        leading: !isWideScreen && (_selectedChannel != null || _selectedRelayRoom != null)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedChannel = null;
                    _selectedRelayRoom = null;
                  });
                },
              )
            : null,
        title: LayoutBuilder(
          builder: (context, constraints) {
            // In narrow screen, show collection title when on channel list
            if (!isWideScreen && _selectedChannel == null && _selectedRelayRoom == null) {
              return Text(widget.collection.title);
            }

            // Show relay room name if selected
            if (_selectedRelayRoom != null) {
              return Text(_selectedRelayRoom!.name);
            }

            return Text(
              _selectedChannel?.name ?? widget.collection.title,
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshChannel,
            tooltip: 'Refresh',
          ),
          if (_selectedChannel != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _showChannelInfo,
              tooltip: 'Channel info',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  /// Build main body
  Widget _buildBody(ThemeData theme) {
    if (!_isInitialized && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
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
              _error!,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _initializeChat,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_channels.isEmpty) {
      return _buildEmptyState(theme);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use two-panel layout for wide screens, single panel for narrow
        final isWideScreen = constraints.maxWidth >= 600;

        if (isWideScreen) {
          // Desktop/landscape: Two-panel layout
          return Row(
            children: [
              // Left sidebar - Channel list with relay rooms
              _buildChannelSidebar(theme),
              // Right panel - Messages and input
              Expanded(
                child: _selectedChannel == null && _selectedRelayRoom == null
                    ? _buildNoChannelSelected(theme)
                    : _selectedRelayRoom != null
                        ? _buildRelayRoomChat(theme)
                        : Column(
                            children: [
                              // Message list
                              Expanded(
                                child: MessageListWidget(
                                  messages: _messages,
                                  isGroupChat: _selectedChannel!.isGroup,
                                  isLoading: _isLoading,
                                  onFileOpen: _openAttachedFile,
                                  onMessageDelete: _deleteMessage,
                                  canDeleteMessage: _canDeleteMessage,
                                ),
                              ),
                              // Message input
                              MessageInputWidget(
                                onSend: _sendMessage,
                                maxLength: _selectedChannel!.config?.maxSizeText ?? 500,
                                allowFiles:
                                    _selectedChannel!.config?.fileUpload ?? true,
                              ),
                            ],
                          ),
              ),
            ],
          );
        } else {
          // Mobile/portrait: Single panel
          if (_selectedChannel == null && _selectedRelayRoom == null) {
            // Show full-width channel list
            return _buildFullWidthChannelList(theme);
          } else if (_selectedRelayRoom != null) {
            // Show relay room messages
            return _buildRelayRoomChat(theme);
          } else {
            // Show chat messages (no duplicate header, using AppBar)
            return Column(
              children: [
                // Message list
                Expanded(
                  child: MessageListWidget(
                    messages: _messages,
                    isGroupChat: _selectedChannel!.isGroup,
                    isLoading: _isLoading,
                    onFileOpen: _openAttachedFile,
                    onMessageDelete: _deleteMessage,
                    canDeleteMessage: _canDeleteMessage,
                  ),
                ),
                // Message input
                MessageInputWidget(
                  onSend: _sendMessage,
                  maxLength: _selectedChannel!.config?.maxSizeText ?? 500,
                  allowFiles: _selectedChannel!.config?.fileUpload ?? true,
                ),
              ],
            );
          }
        }
      },
    );
  }

  /// Build channel sidebar with local channels and relay rooms
  Widget _buildChannelSidebar(ThemeData theme) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Local channels section
          Expanded(
            child: ChannelListWidget(
              channels: _channels,
              selectedChannelId: _selectedChannel?.id,
              onChannelSelect: _selectChannel,
              onNewChannel: _showNewChannelDialog,
            ),
          ),
          // Relay rooms section
          if (_relayRooms.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Relay: ${_relayRooms.first.relayName}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _relayRooms.length,
                itemBuilder: (context, index) {
                  final room = _relayRooms[index];
                  final isSelected = _selectedRelayRoom?.id == room.id;

                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                      child: Icon(
                        Icons.forum,
                        size: 16,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    title: Text(
                      room.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: room.description.isNotEmpty
                        ? Text(
                            room.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          )
                        : null,
                    onTap: () => _selectRelayRoom(room),
                  );
                },
              ),
            ),
          ],
          if (_loadingRelayRooms)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  /// Build relay room chat widget
  Widget _buildRelayRoomChat(ThemeData theme) {
    return Column(
      children: [
        // Room info header
        if (_selectedRelayRoom!.description.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedRelayRoom!.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Message list using converted messages
        Expanded(
          child: MessageListWidget(
            messages: _convertRelayMessages(_relayMessages),
            isGroupChat: true,
            isLoading: _isLoading,
            onFileOpen: (_) {}, // Relay messages don't support file attachments
            onMessageDelete: (_) {}, // Can't delete relay messages
            canDeleteMessage: (_) => false,
          ),
        ),
        // Message input (no file upload for relay)
        MessageInputWidget(
          onSend: _sendMessage,
          maxLength: 1000,
          allowFiles: false,
        ),
      ],
    );
  }

  /// Build full-width channel list for mobile view
  Widget _buildFullWidthChannelList(ThemeData theme) {
    // Sort channels: favorites first, then by last message time
    final sortedChannels = List<ChatChannel>.from(_channels);
    sortedChannels.sort((a, b) {
      // Favorites first
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;

      // Main channel always at top (after favorites)
      if (a.isMain && !b.isMain) return -1;
      if (!a.isMain && b.isMain) return 1;

      // Then by last message time (newest first)
      if (a.lastMessageTime == null && b.lastMessageTime == null) return 0;
      if (a.lastMessageTime == null) return 1;
      if (b.lastMessageTime == null) return -1;
      return b.lastMessageTime!.compareTo(a.lastMessageTime!);
    });

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.chat, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Channels',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showNewChannelDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          // Channel list
          Expanded(
            child: ListView(
              children: [
                // Local channels
                ...sortedChannels.map((channel) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: channel.isGroup
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.secondaryContainer,
                    child: Icon(
                      channel.isGroup ? Icons.group : Icons.person,
                      color: channel.isGroup
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          channel.name,
                          style: TextStyle(
                            fontWeight: channel.isFavorite
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (channel.isFavorite)
                        Icon(
                          Icons.star,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                  subtitle: channel.description != null && channel.description!.isNotEmpty
                      ? Text(
                          channel.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : (channel.isGroup
                          ? const Text('Group chat')
                          : null),
                  onTap: () => _selectChannelMobile(channel),
                )),

                // Relay rooms section
                if (_relayRooms.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cloud, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Relay: ${_relayRooms.first.relayName}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._relayRooms.map((room) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                      child: Icon(
                        Icons.forum,
                        color: theme.colorScheme.onTertiaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(room.name),
                    subtitle: room.description.isNotEmpty
                        ? Text(
                            room.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text('${room.messageCount} messages'),
                    onTap: () => _selectRelayRoom(room),
                  )),
                ],

                // Loading indicator for relay rooms
                if (_loadingRelayRooms)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'No channels found',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a channel to start chatting',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showNewChannelDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Channel'),
          ),
        ],
      ),
    );
  }

  /// Build no channel selected state
  Widget _buildNoChannelSelected(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a channel to start chatting',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Show channel information dialog
  void _showChannelInfo() {
    if (_selectedChannel == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_selectedChannel!.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Type', _selectedChannel!.type.name),
              _buildInfoRow('ID', _selectedChannel!.id),
              if (_selectedChannel!.description != null)
                _buildInfoRow('Description', _selectedChannel!.description!),
              _buildInfoRow('Participants',
                  _selectedChannel!.participants.join(', ')),
              _buildInfoRow('Created',
                  _selectedChannel!.created.toString().substring(0, 16)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build info row
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 12),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
