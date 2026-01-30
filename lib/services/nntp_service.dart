/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * NNTP Service - Manages Usenet newsgroup access
 *
 * NOTE: All file operations use ProfileStorage abstraction.
 * Never use File() or Directory() directly in this service.
 */

import 'dart:async';
import 'dart:convert';

import 'package:nntp/nntp.dart';

import '../models/nntp_account.dart';
import '../models/nntp_subscription.dart';
import '../util/event_bus.dart';
import 'log_service.dart';
import 'profile_service.dart';
import 'profile_storage.dart';

/// Event for NNTP changes
class NNTPChangeEvent {
  final String accountId;
  final NNTPChangeType type;
  final String? groupName;
  final String? messageId;

  NNTPChangeEvent(this.accountId, this.type, {this.groupName, this.messageId});
}

enum NNTPChangeType {
  connected,
  disconnected,
  subscribed,
  unsubscribed,
  newArticles,
  articleRead,
  articlePosted,
  syncStarted,
  syncCompleted,
  error,
}

/// Article thread for UI display
class ArticleThread {
  final OverviewEntry root;
  final List<OverviewEntry> replies;
  final int depth;
  bool isCollapsed;

  ArticleThread({
    required this.root,
    this.replies = const [],
    this.depth = 0,
    this.isCollapsed = false,
  });

  /// Total number of articles in this thread
  int get totalCount => 1 + replies.length;

  /// Most recent article in the thread
  OverviewEntry get mostRecent {
    if (replies.isEmpty) return root;
    return replies.reduce((a, b) {
      final aDate = a.date ?? DateTime(1970);
      final bDate = b.date ?? DateTime(1970);
      return aDate.isAfter(bDate) ? a : b;
    });
  }
}

/// Service for managing NNTP/Usenet access
class NNTPService {
  static final NNTPService _instance = NNTPService._internal();
  factory NNTPService() => _instance;
  NNTPService._internal();

  /// Profile storage abstraction - MUST be set before using the service
  late ProfileStorage _storage;

  /// Connected NNTP clients (account_id -> client)
  final Map<String, NNTPClient> _clients = {};

  /// Registered accounts
  final Map<String, NNTPAccount> _accounts = {};

  /// Subscriptions per account
  final Map<String, Map<String, NNTPSubscription>> _subscriptions = {};

  /// Cached overview data per group
  final Map<String, Map<String, List<OverviewEntry>>> _overviewCache = {};

  /// Stream controller for NNTP events
  final StreamController<NNTPChangeEvent> _eventController =
      StreamController<NNTPChangeEvent>.broadcast();

  /// Stream of NNTP change events
  Stream<NNTPChangeEvent> get onNNTPChange => _eventController.stream;

  /// Whether the service is initialized
  bool _initialized = false;

  /// The callsign for which the service is currently initialized
  String? _initializedForCallsign;

  /// Set the storage implementation
  void setStorage(ProfileStorage storage) {
    _storage = storage;
    _initialized = false;
  }

  /// Initialize NNTP service
  Future<void> initialize() async {
    final profile = ProfileService().getProfile();
    final currentCallsign = profile?.callsign;

    // Re-initialize if profile changed
    if (_initialized && _initializedForCallsign != currentCallsign) {
      _initialized = false;
      await _disconnectAll();
    }

    if (_initialized) return;

    await _ensureDirectoryStructure();
    await _loadAccounts();
    await _loadSubscriptions();

    _initializedForCallsign = currentCallsign;
    _initialized = true;

    LogService().debug('NNTPService initialized');
  }

  /// Ensure directory structure exists
  Future<void> _ensureDirectoryStructure() async {
    final dirs = ['', 'cache', 'drafts'];
    for (final dir in dirs) {
      await _storage.createDirectory(dir);
    }
  }

  /// Load accounts from storage
  Future<void> _loadAccounts() async {
    final json = await _storage.readJson('accounts.json');
    if (json == null) return;

    final accountsList = json['accounts'] as List<dynamic>?;
    if (accountsList == null) return;

    for (final accountJson in accountsList) {
      final account = NNTPAccount.fromJson(accountJson as Map<String, dynamic>);
      _accounts[account.id] = account;
    }
  }

  /// Save accounts to storage
  Future<void> _saveAccounts() async {
    final json = {
      'accounts': _accounts.values.map((a) => a.toJson()).toList(),
    };
    await _storage.writeJson('accounts.json', json);
  }

  /// Load subscriptions from storage
  Future<void> _loadSubscriptions() async {
    final json = await _storage.readJson('subscriptions.json');
    if (json == null) return;

    for (final accountId in json.keys) {
      final accountSubs = json[accountId] as Map<String, dynamic>?;
      if (accountSubs == null) continue;

      _subscriptions[accountId] = {};
      for (final groupName in accountSubs.keys) {
        final subJson = accountSubs[groupName] as Map<String, dynamic>;
        final subscription = NNTPSubscription.fromJson({
          ...subJson,
          'accountId': accountId,
          'groupName': groupName,
        });
        _subscriptions[accountId]![groupName] = subscription;
      }
    }
  }

  /// Save subscriptions to storage
  Future<void> _saveSubscriptions() async {
    final json = <String, dynamic>{};

    for (final entry in _subscriptions.entries) {
      json[entry.key] = <String, dynamic>{};
      for (final sub in entry.value.values) {
        final subJson = sub.toJson();
        subJson.remove('accountId');
        subJson.remove('groupName');
        json[entry.key][sub.groupName] = subJson;
      }
    }

    await _storage.writeJson('subscriptions.json', json);
  }

  // ============================================================
  // Account Management
  // ============================================================

  /// Get all registered accounts
  List<NNTPAccount> get accounts => _accounts.values.toList();

  /// Get a specific account
  NNTPAccount? getAccount(String id) => _accounts[id];

  /// Get connected accounts only
  List<NNTPAccount> get connectedAccounts =>
      _accounts.values.where((a) => a.isConnected).toList();

  /// Add a new account
  Future<void> addAccount(NNTPAccount account) async {
    await initialize();
    _accounts[account.id] = account;
    await _saveAccounts();
  }

  /// Update an existing account
  Future<void> updateAccount(NNTPAccount account) async {
    await initialize();
    _accounts[account.id] = account;
    await _saveAccounts();
  }

  /// Remove an account
  Future<void> removeAccount(String accountId) async {
    await initialize();
    await disconnect(accountId);
    _accounts.remove(accountId);
    _subscriptions.remove(accountId);
    await _saveAccounts();
    await _saveSubscriptions();
  }

  // ============================================================
  // Connection Management
  // ============================================================

  /// Connect to an NNTP server
  Future<void> connect(String accountId) async {
    await initialize();

    final account = _accounts[accountId];
    if (account == null) {
      throw StateError('Account not found: $accountId');
    }

    if (_clients.containsKey(accountId)) {
      LogService().debug('Already connected to $accountId');
      return;
    }

    try {
      final client = NNTPClient(
        host: account.host,
        port: account.port,
        useTLS: account.useTLS,
      );

      await client.connect();

      // Switch to reader mode
      await client.modeReader();

      // Authenticate if credentials provided
      if (account.hasCredentials) {
        await client.authenticate(account.username!, account.password!);
      }

      _clients[accountId] = client;
      account.isConnected = true;
      account.lastConnected = DateTime.now();
      account.capabilities = client.capabilities;
      account.postingAllowed = client.postingAllowed;

      await _saveAccounts();

      _eventController.add(NNTPChangeEvent(accountId, NNTPChangeType.connected));
      LogService().info('Connected to NNTP server: ${account.host}');
    } catch (e) {
      LogService().error('Failed to connect to ${account.host}: $e');
      _eventController.add(NNTPChangeEvent(accountId, NNTPChangeType.error));
      rethrow;
    }
  }

  /// Disconnect from an NNTP server
  Future<void> disconnect(String accountId) async {
    final client = _clients.remove(accountId);
    if (client != null) {
      await client.disconnect();
    }

    final account = _accounts[accountId];
    if (account != null) {
      account.isConnected = false;
      await _saveAccounts();
    }

    _eventController.add(NNTPChangeEvent(accountId, NNTPChangeType.disconnected));
  }

  /// Disconnect all connections
  Future<void> _disconnectAll() async {
    for (final accountId in _clients.keys.toList()) {
      await disconnect(accountId);
    }
  }

  /// Get client for an account (connects if needed)
  Future<NNTPClient> _getClient(String accountId) async {
    if (!_clients.containsKey(accountId)) {
      await connect(accountId);
    }
    return _clients[accountId]!;
  }

  // ============================================================
  // Newsgroup Operations
  // ============================================================

  /// List all newsgroups on a server
  Future<List<Newsgroup>> listGroups(String accountId, {String? pattern}) async {
    await initialize();
    final client = await _getClient(accountId);
    return client.listGroups(pattern: pattern);
  }

  /// Get newsgroup descriptions
  Future<Map<String, String>> getGroupDescriptions(
    String accountId, {
    String? pattern,
  }) async {
    await initialize();
    final client = await _getClient(accountId);
    return client.listDescriptions(pattern: pattern);
  }

  /// Subscribe to a newsgroup
  Future<void> subscribe(String accountId, String groupName, {String? description}) async {
    await initialize();

    // Verify the group exists
    final client = await _getClient(accountId);
    final group = await client.selectGroup(groupName);

    // Create subscription
    final subscription = NNTPSubscription(
      accountId: accountId,
      groupName: groupName,
      description: description,
      firstArticle: group.firstArticle,
      lastArticle: group.lastArticle,
      estimatedCount: group.estimatedCount,
      postingAllowed: group.postingAllowed,
    );

    _subscriptions.putIfAbsent(accountId, () => {});
    _subscriptions[accountId]![groupName] = subscription;

    await _saveSubscriptions();

    _eventController.add(NNTPChangeEvent(
      accountId,
      NNTPChangeType.subscribed,
      groupName: groupName,
    ));
  }

  /// Unsubscribe from a newsgroup
  Future<void> unsubscribe(String accountId, String groupName) async {
    await initialize();

    _subscriptions[accountId]?.remove(groupName);
    _overviewCache[accountId]?.remove(groupName);

    // Delete cached articles
    await _storage.deleteDirectory('cache/$accountId/$groupName', recursive: true);

    await _saveSubscriptions();

    _eventController.add(NNTPChangeEvent(
      accountId,
      NNTPChangeType.unsubscribed,
      groupName: groupName,
    ));
  }

  /// Get subscriptions for an account
  List<NNTPSubscription> getSubscriptions(String accountId) {
    return _subscriptions[accountId]?.values.toList() ?? [];
  }

  /// Get all subscriptions across all accounts
  List<NNTPSubscription> get allSubscriptions {
    return _subscriptions.values.expand((m) => m.values).toList();
  }

  /// Get a specific subscription
  NNTPSubscription? getSubscription(String accountId, String groupName) {
    return _subscriptions[accountId]?[groupName];
  }

  // ============================================================
  // Article Operations
  // ============================================================

  /// Fetch overview data for a group
  Future<List<OverviewEntry>> fetchOverview(
    String accountId,
    String groupName, {
    Range? range,
    bool useCache = true,
  }) async {
    await initialize();

    // Check cache first
    if (useCache) {
      final cached = _overviewCache[accountId]?[groupName];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final client = await _getClient(accountId);

    // Select group first
    await client.selectGroup(groupName);

    // Fetch overview
    final entries = await client.fetchOverview(range: range);

    // Update cache
    _overviewCache.putIfAbsent(accountId, () => {});
    _overviewCache[accountId]![groupName] = entries;

    // Save cache to storage
    await _cacheOverview(accountId, groupName, entries);

    return entries;
  }

  /// Cache overview data to storage
  Future<void> _cacheOverview(
    String accountId,
    String groupName,
    List<OverviewEntry> entries,
  ) async {
    final cachePath = 'cache/$accountId/$groupName';
    await _storage.createDirectory(cachePath);

    final json = {
      'cachedAt': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };

    await _storage.writeJson('$cachePath/overview.json', json);
  }

  /// Load cached overview data
  Future<List<OverviewEntry>?> _loadCachedOverview(
    String accountId,
    String groupName,
  ) async {
    final json = await _storage.readJson('cache/$accountId/$groupName/overview.json');
    if (json == null) return null;

    final entriesList = json['entries'] as List<dynamic>?;
    if (entriesList == null) return null;

    return entriesList
        .map((e) => OverviewEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a complete article
  Future<NNTPArticle> fetchArticle(
    String accountId,
    String groupName,
    int articleNumber,
  ) async {
    await initialize();

    // Check cache first
    final cached = await _loadCachedArticle(accountId, groupName, articleNumber);
    if (cached != null) return cached;

    final client = await _getClient(accountId);

    // Select group first
    await client.selectGroup(groupName);

    // Fetch article
    final article = await client.fetchArticle(articleNumber);

    // Cache article
    await _cacheArticle(accountId, groupName, article);

    return article;
  }

  /// Fetch article by message ID
  Future<NNTPArticle> fetchArticleById(String accountId, String messageId) async {
    await initialize();
    final client = await _getClient(accountId);
    return client.fetchArticleById(messageId);
  }

  /// Cache an article to storage
  Future<void> _cacheArticle(
    String accountId,
    String groupName,
    NNTPArticle article,
  ) async {
    final cachePath = 'cache/$accountId/$groupName/articles';
    await _storage.createDirectory(cachePath);

    final content = _formatArticleMarkdown(article);
    await _storage.writeString(
      '$cachePath/${article.articleNumber ?? article.messageId.hashCode}.md',
      content,
    );
  }

  /// Load cached article
  Future<NNTPArticle?> _loadCachedArticle(
    String accountId,
    String groupName,
    int articleNumber,
  ) async {
    final content = await _storage.readString(
      'cache/$accountId/$groupName/articles/$articleNumber.md',
    );
    if (content == null) return null;

    return _parseArticleMarkdown(content);
  }

  /// Format article as markdown for storage
  String _formatArticleMarkdown(NNTPArticle article) {
    final buffer = StringBuffer();

    buffer.writeln('# ARTICLE: ${article.subject}');
    buffer.writeln();
    buffer.writeln('MESSAGE-ID: ${article.messageId}');
    buffer.writeln('FROM: ${article.from}');
    buffer.writeln('NEWSGROUPS: ${article.newsgroups}');
    buffer.writeln('DATE: ${article.date.toUtc().toIso8601String()}');
    if (article.references != null) {
      buffer.writeln('REFERENCES: ${article.references}');
    }
    buffer.writeln('SUBJECT: ${article.subject}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.write(article.body);

    return buffer.toString();
  }

  /// Parse article from markdown storage
  NNTPArticle? _parseArticleMarkdown(String content) {
    final lines = content.split('\n');
    final headers = <String, String>{};
    final bodyLines = <String>[];
    var inBody = false;

    for (var line in lines) {
      if (line.startsWith('# ARTICLE:')) continue;

      if (line == '---') {
        inBody = true;
        continue;
      }

      if (!inBody) {
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          final key = line.substring(0, colonIndex).toLowerCase();
          final value = line.substring(colonIndex + 1).trim();
          headers[key] = value;
        }
      } else {
        bodyLines.add(line);
      }
    }

    final messageId = headers['message-id'];
    if (messageId == null) return null;

    return NNTPArticle(
      messageId: messageId,
      subject: headers['subject'] ?? '',
      from: headers['from'] ?? '',
      date: DateTime.tryParse(headers['date'] ?? '') ?? DateTime.now(),
      references: headers['references'],
      newsgroups: headers['newsgroups'] ?? '',
      body: bodyLines.join('\n').trim(),
      headers: headers,
    );
  }

  // ============================================================
  // Posting Operations
  // ============================================================

  /// Post a new article
  Future<void> post(String accountId, NNTPArticle article) async {
    await initialize();

    final client = await _getClient(accountId);
    await client.post(article);

    _eventController.add(NNTPChangeEvent(
      accountId,
      NNTPChangeType.articlePosted,
      groupName: article.newsgroups,
      messageId: article.messageId,
    ));
  }

  /// Save a draft article
  Future<void> saveDraft(NNTPArticle article) async {
    await initialize();

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final content = _formatArticleMarkdown(article);

    await _storage.writeString('drafts/$id.md', content);
  }

  /// Load all drafts
  Future<List<NNTPArticle>> loadDrafts() async {
    await initialize();

    final entries = await _storage.listDirectory('drafts');
    final drafts = <NNTPArticle>[];

    for (final entry in entries) {
      if (!entry.name.endsWith('.md')) continue;
      final content = await _storage.readString(entry.path);
      if (content == null) continue;

      final article = _parseArticleMarkdown(content);
      if (article != null) {
        drafts.add(article);
      }
    }

    return drafts;
  }

  /// Delete a draft
  Future<void> deleteDraft(String draftId) async {
    await initialize();
    await _storage.delete('drafts/$draftId.md');
  }

  // ============================================================
  // Threading Operations
  // ============================================================

  /// Build threads from overview entries
  List<ArticleThread> buildThreads(List<OverviewEntry> entries) {
    // Map message-id to entry
    final byMessageId = <String, OverviewEntry>{};
    for (final entry in entries) {
      byMessageId[entry.messageId] = entry;
    }

    // Find root articles (no parent in our list)
    final roots = <OverviewEntry>[];
    final children = <String, List<OverviewEntry>>{};

    for (final entry in entries) {
      final parentId = entry.parentMessageId;

      if (parentId == null || !byMessageId.containsKey(parentId)) {
        roots.add(entry);
      } else {
        children.putIfAbsent(parentId, () => []).add(entry);
      }
    }

    // Build threads recursively
    List<OverviewEntry> collectReplies(String messageId) {
      final replies = <OverviewEntry>[];
      final direct = children[messageId] ?? [];

      for (final child in direct) {
        replies.add(child);
        replies.addAll(collectReplies(child.messageId));
      }

      return replies;
    }

    final threads = <ArticleThread>[];
    for (final root in roots) {
      threads.add(ArticleThread(
        root: root,
        replies: collectReplies(root.messageId),
      ));
    }

    // Sort threads by most recent activity
    threads.sort((a, b) {
      final aDate = a.mostRecent.date ?? DateTime(1970);
      final bDate = b.mostRecent.date ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });

    return threads;
  }

  // ============================================================
  // Sync Operations
  // ============================================================

  /// Sync a subscribed group
  Future<void> syncGroup(String accountId, String groupName) async {
    await initialize();

    final subscription = _subscriptions[accountId]?[groupName];
    if (subscription == null) {
      throw StateError('Not subscribed to $groupName');
    }

    _eventController.add(NNTPChangeEvent(
      accountId,
      NNTPChangeType.syncStarted,
      groupName: groupName,
    ));

    try {
      final client = await _getClient(accountId);
      final group = await client.selectGroup(groupName);

      subscription.updateFromGroup(
        first: group.firstArticle,
        last: group.lastArticle,
        count: group.estimatedCount,
      );

      // Fetch recent articles
      final range = subscription.lastRead > 0
          ? Range(subscription.lastRead + 1, group.lastArticle)
          : Range(group.lastArticle - 100, group.lastArticle);

      await fetchOverview(accountId, groupName, range: range, useCache: false);

      await _saveSubscriptions();

      _eventController.add(NNTPChangeEvent(
        accountId,
        NNTPChangeType.syncCompleted,
        groupName: groupName,
      ));

      if (subscription.unreadCount > 0) {
        _eventController.add(NNTPChangeEvent(
          accountId,
          NNTPChangeType.newArticles,
          groupName: groupName,
        ));
      }
    } catch (e) {
      LogService().error('Failed to sync $groupName: $e');
      _eventController.add(NNTPChangeEvent(
        accountId,
        NNTPChangeType.error,
        groupName: groupName,
      ));
      rethrow;
    }
  }

  /// Sync all subscribed groups for an account
  Future<void> syncAllGroups(String accountId) async {
    final subs = getSubscriptions(accountId);
    for (final sub in subs) {
      try {
        await syncGroup(accountId, sub.groupName);
      } catch (e) {
        LogService().error('Failed to sync ${sub.groupName}: $e');
      }
    }
  }

  /// Mark articles as read
  Future<void> markAsRead(
    String accountId,
    String groupName, {
    int? upToArticle,
    bool all = false,
  }) async {
    await initialize();

    final subscription = _subscriptions[accountId]?[groupName];
    if (subscription == null) return;

    if (all) {
      subscription.markAllRead();
    } else if (upToArticle != null) {
      subscription.markReadUpTo(upToArticle);
    }

    await _saveSubscriptions();

    _eventController.add(NNTPChangeEvent(
      accountId,
      NNTPChangeType.articleRead,
      groupName: groupName,
    ));
  }

  // ============================================================
  // Offline Operations
  // ============================================================

  /// Get cached articles for offline reading
  Future<List<NNTPArticle>> getOfflineArticles(
    String accountId,
    String groupName,
  ) async {
    await initialize();

    final entries = await _storage.listDirectory(
      'cache/$accountId/$groupName/articles',
    );
    final articles = <NNTPArticle>[];

    for (final entry in entries) {
      if (!entry.name.endsWith('.md')) continue;
      final content = await _storage.readString(entry.path);
      if (content == null) continue;

      final article = _parseArticleMarkdown(content);
      if (article != null) {
        articles.add(article);
      }
    }

    return articles;
  }

  /// Clear cache for a group
  Future<void> clearCache(String accountId, String groupName) async {
    await initialize();
    _overviewCache[accountId]?.remove(groupName);
    await _storage.deleteDirectory('cache/$accountId/$groupName', recursive: true);
  }

  /// Clear all caches
  Future<void> clearAllCaches() async {
    await initialize();
    _overviewCache.clear();
    await _storage.deleteDirectory('cache', recursive: true);
    await _storage.createDirectory('cache');
  }

  /// Dispose resources
  void dispose() {
    _disconnectAll();
    _eventController.close();
  }
}
