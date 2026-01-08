/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/collection_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';

/// Full-page UI for creating a new collection
/// Features a two-column layout: type selector on left, details panel on right
class CreateCollectionPage extends StatefulWidget {
  const CreateCollectionPage({super.key});

  @override
  State<CreateCollectionPage> createState() => _CreateCollectionPageState();
}

class _CreateCollectionPageState extends State<CreateCollectionPage> {
  final I18nService _i18n = I18nService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedType;
  String _visibility = 'public';
  bool _useAutoFolder = true;
  String? _selectedFolderPath;
  bool _isCreating = false;
  Set<String> _existingTypes = {};
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  /// Get app types sorted alphabetically by localized name
  List<_CollectionTypeInfo> get _sortedTypes {
    final types = List<_CollectionTypeInfo>.from(_collectionTypes);
    types.sort((a, b) => _i18n.t('collection_type_${a.type}')
        .toLowerCase()
        .compareTo(_i18n.t('collection_type_${b.type}').toLowerCase()));
    return types;
  }

  // Collection types with their icons (ordered by relevance)
  // Hidden types (not ready): forum, transfer, bot, postcards, market, www, news
  static const List<_CollectionTypeInfo> _collectionTypes = [
    _CollectionTypeInfo('places', Icons.place),
    _CollectionTypeInfo('blog', Icons.article),
    _CollectionTypeInfo('chat', Icons.chat),
    _CollectionTypeInfo('contacts', Icons.contacts),
    _CollectionTypeInfo('events', Icons.event),
    // _CollectionTypeInfo('forum', Icons.forum),  // Hidden: not ready
    _CollectionTypeInfo('alerts', Icons.campaign),
    // _CollectionTypeInfo('news', Icons.newspaper),  // Hidden: not ready
    // _CollectionTypeInfo('www', Icons.language),  // Hidden: not ready
    _CollectionTypeInfo('inventory', Icons.inventory_2),
    _CollectionTypeInfo('wallet', Icons.account_balance_wallet),
    _CollectionTypeInfo('log', Icons.article_outlined),
    _CollectionTypeInfo('backup', Icons.backup),
    // _CollectionTypeInfo('transfer', Icons.swap_horiz),  // Hidden: not ready
    _CollectionTypeInfo('files', Icons.folder),
    // _CollectionTypeInfo('postcards', Icons.mail),  // Hidden: not ready
    // _CollectionTypeInfo('market', Icons.storefront),  // Hidden: not ready
    _CollectionTypeInfo('groups', Icons.groups),
    _CollectionTypeInfo('console', Icons.terminal),
    _CollectionTypeInfo('tracker', Icons.track_changes),
  ];

  // Single-instance types (all except 'files')
  static const Set<String> _singleInstanceTypes = {
    'forum', 'chat', 'blog', 'events', 'news', 'www',
    'postcards', 'places', 'market', 'alerts', 'groups', 'backup', 'transfer', 'inventory', 'wallet', 'log', 'console', 'tracker'
  };

  @override
  void initState() {
    super.initState();
    _checkExistingTypes();
  }

  Future<void> _checkExistingTypes() async {
    try {
      final collectionsService = CollectionService();
      final collectionsDir = Directory('${collectionsService.getDefaultCollectionsPath()}');

      if (await collectionsDir.exists()) {
        final folders = await collectionsDir.list().toList();
        final existingFolderNames = folders
            .where((e) => e is Directory)
            .map((e) => e.path.split('/').last)
            .toSet();

        setState(() {
          _existingTypes = _singleInstanceTypes.intersection(existingFolderNames);
          // Initialize item keys for scroll-to functionality
          for (final type in _collectionTypes) {
            _itemKeys[type.type] = GlobalKey();
          }
        });
      }
    } catch (e) {
      LogService().log('Error checking existing types: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canCreate {
    if (_isCreating) return false;
    if (_selectedType == null) return false;
    if (_selectedType == 'files') {
      if (_titleController.text.trim().isEmpty) return false;
      if (!_useAutoFolder && _selectedFolderPath == null) return false;
    } else {
      if (_existingTypes.contains(_selectedType)) return false;
    }
    return true;
  }

  Future<void> _pickFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select root folder for collection',
      );

      if (result != null) {
        setState(() {
          _selectedFolderPath = result;
        });
      }
    } catch (e) {
      LogService().log('Error picking folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting folder: $e')),
        );
      }
    }
  }

  Future<void> _create() async {
    if (!_canCreate || _selectedType == null) return;

    setState(() => _isCreating = true);

    try {
      final type = _selectedType!;
      final title = type == 'files'
          ? _titleController.text.trim()
          : _i18n.t('collection_type_$type');

      final collection = await CollectionService().createCollection(
        title: title,
        description: _descriptionController.text.trim(),
        type: type,
        customRootPath: type == 'files'
            ? (_useAutoFolder ? null : _selectedFolderPath)
            : null,
      );

      // Update visibility if not public
      if (type == 'files' && _visibility != 'public') {
        collection.visibility = _visibility;
        await CollectionService().updateCollection(collection);
      }

      LogService().log('Created collection: ${collection.title}');

      if (mounted) {
        Navigator.pop(context, collection);
      }
    } catch (e, stackTrace) {
      LogService().log('ERROR creating collection: $e');
      LogService().log('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating collection: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('add_new_collection')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildAppList(),
    );
  }

  Widget _buildAppList() {
    final sortedTypes = _sortedTypes;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedTypes.length,
      itemBuilder: (context, index) => _buildAppListItem(sortedTypes[index]),
    );
  }

  /// Get a gradient for the app type icon
  LinearGradient _getTypeGradient(String type, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    switch (type) {
      case 'chat':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1565C0), const Color(0xFF0D47A1)]
              : [const Color(0xFF42A5F5), const Color(0xFF1E88E5)],
        );
      case 'blog':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFFAD1457), const Color(0xFF880E4F)]
              : [const Color(0xFFEC407A), const Color(0xFFD81B60)],
        );
      case 'places':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2E7D32), const Color(0xFF1B5E20)]
              : [const Color(0xFF66BB6A), const Color(0xFF43A047)],
        );
      case 'events':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFFE65100), const Color(0xFFBF360C)]
              : [const Color(0xFFFF9800), const Color(0xFFF57C00)],
        );
      case 'alerts':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFFC62828), const Color(0xFFB71C1C)]
              : [const Color(0xFFEF5350), const Color(0xFFE53935)],
        );
      case 'backup':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF00838F), const Color(0xFF006064)]
              : [const Color(0xFF26C6DA), const Color(0xFF00ACC1)],
        );
      case 'inventory':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF6A1B9A), const Color(0xFF4A148C)]
              : [const Color(0xFFAB47BC), const Color(0xFF8E24AA)],
        );
      case 'wallet':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF558B2F), const Color(0xFF33691E)]
              : [const Color(0xFF9CCC65), const Color(0xFF7CB342)],
        );
      case 'contacts':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF5D4037), const Color(0xFF4E342E)]
              : [const Color(0xFF8D6E63), const Color(0xFF6D4C41)],
        );
      case 'groups':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0277BD), const Color(0xFF01579B)]
              : [const Color(0xFF29B6F6), const Color(0xFF039BE5)],
        );
      case 'files':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF455A64), const Color(0xFF37474F)]
              : [const Color(0xFF78909C), const Color(0xFF607D8B)],
        );
      case 'log':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF37474F), const Color(0xFF263238)]
              : [const Color(0xFF546E7A), const Color(0xFF455A64)],
        );
      case 'console':
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1A237E), const Color(0xFF0D47A1)]
              : [const Color(0xFF3F51B5), const Color(0xFF303F9F)],
        );
      default:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [theme.colorScheme.primary.withValues(alpha: 0.8), theme.colorScheme.primary]
              : [theme.colorScheme.primary.withValues(alpha: 0.8), theme.colorScheme.primary],
        );
    }
  }

  Widget _buildAppListItem(_CollectionTypeInfo typeInfo) {
    final theme = Theme.of(context);
    final isDisabled = _existingTypes.contains(typeInfo.type) &&
        _singleInstanceTypes.contains(typeInfo.type);
    final isExpanded = _selectedType == typeInfo.type;
    final description = _getTypeDescription(typeInfo.type);
    final features = _getTypeFeatures(typeInfo.type);

    return Padding(
      key: _itemKeys[typeInfo.type],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: isExpanded
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isDisabled
              ? null
              : () {
                  setState(() {
                    _selectedType = isExpanded ? null : typeInfo.type;
                    // Clear title when collapsing or switching types
                    if (!isExpanded && typeInfo.type != 'files') {
                      _titleController.clear();
                    }
                  });
                  // Scroll to make expanded item visible
                  if (!isExpanded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final key = _itemKeys[typeInfo.type];
                      if (key?.currentContext != null) {
                        Scrollable.ensureVisible(
                          key!.currentContext!,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    });
                  }
                },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header (always visible)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Circular gradient icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _getTypeGradient(typeInfo.type, theme),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getTypeGradient(typeInfo.type, theme).colors.first.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        typeInfo.icon,
                        size: 26,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Title + short description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _i18n.t('collection_type_${typeInfo.type}'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: isExpanded ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status badge or expand indicator
                    if (isDisabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _i18n.t('exists'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Expanded details with animation
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: isExpanded
                    ? _buildExpandedDetails(typeInfo, theme, description, features)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(
    _CollectionTypeInfo typeInfo,
    ThemeData theme,
    String description,
    List<String> features,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Subtle divider
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Features as horizontal chips
              if (features.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: features.map((f) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          f,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ],
              // Settings for 'files' type
              if (typeInfo.type == 'files') ...[
                const SizedBox(height: 20),
                _buildFilesSettings(theme),
              ],
              const SizedBox(height: 24),
              // Create button - more prominent
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _canCreate ? _create : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isCreating
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_circle_outline, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              _i18n.t('create'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilesSettings(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Icon(
                Icons.settings_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _i18n.t('settings'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Title field
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: _i18n.t('collection_title'),
              hintText: _i18n.t('collection_title_hint'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.title),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            enabled: !_isCreating,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Visibility dropdown
          DropdownButtonFormField<String>(
            value: _visibility,
            decoration: InputDecoration(
              labelText: _i18n.t('visibility'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.visibility_outlined),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
            items: [
              DropdownMenuItem(
                value: 'public',
                child: Text(_i18n.t('visibility_public')),
              ),
              DropdownMenuItem(
                value: 'private',
                child: Text(_i18n.t('visibility_private')),
              ),
              DropdownMenuItem(
                value: 'restricted',
                child: Text(_i18n.t('visibility_restricted')),
              ),
            ],
            onChanged: _isCreating
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _visibility = value;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),

          // Storage location toggle
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _i18n.t('storage_location'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _useAutoFolder
                                ? '~/Documents/geogram/devices/${CollectionService().currentCallsign ?? "..."}'
                                : _i18n.t('choose_custom_location'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _useAutoFolder,
                      onChanged: _isCreating
                          ? null
                          : (value) {
                              setState(() {
                                _useAutoFolder = value;
                                if (_useAutoFolder) {
                                  _selectedFolderPath = null;
                                }
                              });
                            },
                    ),
                  ],
                ),

                // Custom folder picker
                if (!_useAutoFolder) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isCreating ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: Text(_i18n.t('choose_folder')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_selectedFolderPath != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedFolderPath!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeDescription(String type) {
    // Try to get from i18n, fallback to default descriptions
    final key = 'collection_type_desc_$type';
    final translated = _i18n.t(key);
    if (translated != key) return translated;

    // Fallback descriptions
    switch (type) {
      case 'files':
        return 'Store and organize files in custom folders. Create multiple collections for different purposes like documents, photos, or projects.';
      case 'forum':
        return 'Discussion forum for threaded conversations and community discussions. Topics are organized by categories with support for replies and moderation.';
      case 'chat':
        return 'Real-time messaging with support for multiple channels. Perfect for team communication or group discussions.';
      case 'blog':
        return 'Publish articles and posts for sharing your thoughts, tutorials, or updates. Supports rich content with images and formatting.';
      case 'events':
        return 'Create and manage events with dates, times, locations, and attendee registration. Great for organizing meetups or activities.';
      case 'news':
        return 'Share news and announcements with your network. Keep your community informed about updates and important information.';
      case 'www':
        return 'Host a personal website with full HTML, CSS, and JavaScript support. Accessible via your station URL.';
      case 'postcards':
        return 'Send and receive digital postcards with images and personal messages. A fun way to share memories and greetings.';
      case 'contacts':
        return 'Store contact information for people and organizations. Keep your network organized and accessible.';
      case 'places':
        return 'Save and share locations with maps, coordinates, and descriptions. Document interesting places or share recommendations.';
      case 'market':
        return 'List items for sale, trade, or giveaway. A simple marketplace for your community.';
      case 'alerts':
        return 'Receive and manage alerts and notifications. Stay informed about important updates and events in your network.';
      case 'groups':
        return 'Organize people into groups for easier management and communication. Create teams or interest groups.';
      case 'backup':
        return 'Securely backup your data to other devices with end-to-end encryption. Your data stays private while being safely stored across trusted contacts.';
      case 'inventory':
        return 'Track and manage your items with folder-based organization. Keep track of quantities, usage, expiry dates, and borrowed items.';
      case 'station':
        return 'Station configuration for network communication settings. Manage how your node connects to the network.';
      case 'console':
        return 'Run Alpine Linux virtual machines with TinyEMU emulator. Access a full Linux terminal, mount host folders, and connect to network services.';
      default:
        return '';
    }
  }

  List<String> _getTypeFeatures(String type) {
    // Try to get from i18n first
    final key = 'collection_type_features_$type';
    final translated = _i18n.t(key);
    if (translated != key) {
      return translated.split('|');
    }

    // Fallback features
    switch (type) {
      case 'files':
        return [
          'Organize files by folders',
          'Share with specific users',
          'Set visibility permissions',
          'Multiple collections allowed',
        ];
      case 'forum':
        return [
          'Threaded discussions',
          'Categories and topics',
          'User moderation',
          'Pinned topics',
        ];
      case 'chat':
        return [
          'Multiple channels',
          'Text, image, and file sharing',
          'Message history',
          'Participant management',
        ];
      case 'blog':
        return [
          'Rich text editor',
          'Image embedding',
          'Draft saving',
          'Post scheduling',
        ];
      case 'events':
        return [
          'Date/time scheduling',
          'Location mapping',
          'Registration',
          'Reminders',
        ];
      case 'news':
        return [
          'Chronological feed',
          'Categories',
          'Featured posts',
          'Notifications',
        ];
      case 'www':
        return [
          'Full web hosting',
          'Custom HTML/CSS/JS',
          'Accessible at station-url/callsign',
        ];
      case 'postcards':
        return [
          'Image attachments',
          'Personal messages',
          'Send/receive tracking',
        ];
      case 'contacts':
        return [
          'Contact details',
          'Organization info',
          'Search',
          'Export',
        ];
      case 'places':
        return [
          'Map integration',
          'Coordinates',
          'Descriptions',
          'Photos',
        ];
      case 'market':
        return [
          'Item listings',
          'Pricing',
          'Categories',
          'Contact seller',
        ];
      case 'alerts':
        return [
          'Real-time notifications',
          'Priority levels',
          'Alert history',
          'Custom filters',
        ];
      case 'groups':
        return [
          'Member management',
          'Group roles',
          'Bulk actions',
        ];
      case 'backup':
        return [
          'End-to-end encryption',
          'Multiple providers',
          'Automatic scheduling',
          'Full restore support',
        ];
      case 'inventory':
        return [
          'Folder-based organization',
          'Quantity and usage tracking',
          'Batch/lot management with expiry',
          'Borrowing and lending',
          '200+ item types with templates',
        ];
      case 'station':
        return [
          'Connection settings',
          'Peer management',
          'Bandwidth controls',
        ];
      case 'console':
        return [
          'Alpine Linux VM',
          'Mount host folders',
          'Network access',
          'Save/restore state',
        ];
      default:
        return [];
    }
  }
}

/// Helper class for collection type information
class _CollectionTypeInfo {
  final String type;
  final IconData icon;

  const _CollectionTypeInfo(this.type, this.icon);
}
