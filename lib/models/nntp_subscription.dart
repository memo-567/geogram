/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * NNTP Subscription Model - Represents a subscribed newsgroup
 */

/// Represents a subscription to a newsgroup on an NNTP server.
class NNTPSubscription {
  /// Account ID this subscription belongs to.
  final String accountId;

  /// Full newsgroup name (e.g., "comp.lang.dart").
  final String groupName;

  /// Human-readable description of the group.
  final String? description;

  /// High water mark when last synced.
  int lastRead;

  /// Estimated total article count.
  int estimatedCount;

  /// Number of unread articles.
  int unreadCount;

  /// First article number in the group.
  int firstArticle;

  /// Last article number in the group.
  int lastArticle;

  /// When the subscription was created.
  final DateTime subscribedAt;

  /// When last synced.
  DateTime? lastSyncedAt;

  /// Whether posting is allowed to this group.
  final bool postingAllowed;

  /// Custom sort order (lower = higher priority).
  int sortOrder;

  /// Whether notifications are enabled.
  bool notificationsEnabled;

  NNTPSubscription({
    required this.accountId,
    required this.groupName,
    this.description,
    this.lastRead = 0,
    this.estimatedCount = 0,
    this.unreadCount = 0,
    this.firstArticle = 0,
    this.lastArticle = 0,
    DateTime? subscribedAt,
    this.lastSyncedAt,
    this.postingAllowed = true,
    this.sortOrder = 0,
    this.notificationsEnabled = true,
  }) : subscribedAt = subscribedAt ?? DateTime.now();

  /// Group hierarchy (e.g., ["comp", "lang", "dart"]).
  List<String> get hierarchy => groupName.split('.');

  /// Top-level hierarchy (e.g., "comp").
  String get topLevel => hierarchy.first;

  /// Short name (last part of hierarchy).
  String get shortName => hierarchy.last;

  /// Display name (description or short name).
  String get displayName => description ?? shortName;

  /// Whether there are unread articles.
  bool get hasUnread => unreadCount > 0;

  /// Whether the group has been synced at least once.
  bool get isSynced => lastSyncedAt != null;

  /// Update sync state from group info.
  void updateFromGroup({
    required int first,
    required int last,
    required int count,
  }) {
    firstArticle = first;
    lastArticle = last;
    estimatedCount = count;

    // Calculate unread count
    if (lastRead > 0 && last > lastRead) {
      unreadCount = last - lastRead;
    } else if (lastRead == 0) {
      // First sync - all articles are "unread"
      unreadCount = count;
    }

    lastSyncedAt = DateTime.now();
  }

  /// Mark articles as read up to a given article number.
  void markReadUpTo(int articleNumber) {
    if (articleNumber > lastRead) {
      lastRead = articleNumber;
      unreadCount = lastArticle > lastRead ? lastArticle - lastRead : 0;
    }
  }

  /// Mark all articles as read.
  void markAllRead() {
    lastRead = lastArticle;
    unreadCount = 0;
  }

  /// Create from JSON.
  factory NNTPSubscription.fromJson(Map<String, dynamic> json) {
    return NNTPSubscription(
      accountId: json['accountId'] as String,
      groupName: json['groupName'] as String,
      description: json['description'] as String?,
      lastRead: json['lastRead'] as int? ?? 0,
      estimatedCount: json['estimatedCount'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? 0,
      firstArticle: json['firstArticle'] as int? ?? 0,
      lastArticle: json['lastArticle'] as int? ?? 0,
      subscribedAt: json['subscribedAt'] != null
          ? DateTime.parse(json['subscribedAt'] as String)
          : null,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'] as String)
          : null,
      postingAllowed: json['postingAllowed'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'groupName': groupName,
        if (description != null) 'description': description,
        'lastRead': lastRead,
        'estimatedCount': estimatedCount,
        'unreadCount': unreadCount,
        'firstArticle': firstArticle,
        'lastArticle': lastArticle,
        'subscribedAt': subscribedAt.toIso8601String(),
        if (lastSyncedAt != null) 'lastSyncedAt': lastSyncedAt!.toIso8601String(),
        'postingAllowed': postingAllowed,
        'sortOrder': sortOrder,
        'notificationsEnabled': notificationsEnabled,
      };

  /// Create a copy with modified fields.
  NNTPSubscription copyWith({
    String? accountId,
    String? groupName,
    String? description,
    int? lastRead,
    int? estimatedCount,
    int? unreadCount,
    int? firstArticle,
    int? lastArticle,
    DateTime? subscribedAt,
    DateTime? lastSyncedAt,
    bool? postingAllowed,
    int? sortOrder,
    bool? notificationsEnabled,
  }) {
    return NNTPSubscription(
      accountId: accountId ?? this.accountId,
      groupName: groupName ?? this.groupName,
      description: description ?? this.description,
      lastRead: lastRead ?? this.lastRead,
      estimatedCount: estimatedCount ?? this.estimatedCount,
      unreadCount: unreadCount ?? this.unreadCount,
      firstArticle: firstArticle ?? this.firstArticle,
      lastArticle: lastArticle ?? this.lastArticle,
      subscribedAt: subscribedAt ?? this.subscribedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      postingAllowed: postingAllowed ?? this.postingAllowed,
      sortOrder: sortOrder ?? this.sortOrder,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NNTPSubscription &&
        other.accountId == accountId &&
        other.groupName == groupName;
  }

  @override
  int get hashCode => Object.hash(accountId, groupName);

  @override
  String toString() => 'NNTPSubscription($groupName, unread: $unreadCount)';
}
