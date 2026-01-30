/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * NNTP Account Model - Represents a Usenet server connection
 */

/// Represents an NNTP/Usenet server account configuration.
///
/// Each account represents a connection to a single NNTP server,
/// which may host many newsgroups.
class NNTPAccount {
  /// Unique account identifier.
  final String id;

  /// Display name for the account.
  final String name;

  /// Server hostname (e.g., "news.eternal-september.org").
  final String host;

  /// Server port (119 for NNTP, 563 for NNTPS).
  final int port;

  /// Whether to use TLS/SSL.
  final bool useTLS;

  /// Username for authentication (optional).
  final String? username;

  /// Password for authentication (optional).
  final String? password;

  /// Whether currently connected to this server.
  bool isConnected;

  /// Last successful connection time.
  DateTime? lastConnected;

  /// Server capabilities (populated after connection).
  Set<String> capabilities;

  /// Whether posting is allowed on this server.
  bool postingAllowed;

  /// Maximum article retention days (if known).
  int? retentionDays;

  NNTPAccount({
    required this.id,
    required this.name,
    required this.host,
    this.port = 119,
    this.useTLS = false,
    this.username,
    this.password,
    this.isConnected = false,
    this.lastConnected,
    this.capabilities = const {},
    this.postingAllowed = true,
    this.retentionDays,
  });

  /// Creates a default account for a known server.
  factory NNTPAccount.eternalSeptember({
    required String username,
    required String password,
  }) {
    return NNTPAccount(
      id: 'eternal-september',
      name: 'Eternal September',
      host: 'news.eternal-september.org',
      port: 119,
      useTLS: false,
      username: username,
      password: password,
    );
  }

  /// Creates a read-only account for Gmane (no auth required).
  factory NNTPAccount.gmane() {
    return NNTPAccount(
      id: 'gmane',
      name: 'Gmane',
      host: 'news.gmane.io',
      port: 119,
      useTLS: false,
      postingAllowed: false,
    );
  }

  /// Connection string for display.
  String get connectionString {
    final protocol = useTLS ? 'nntps' : 'nntp';
    final defaultPort = useTLS ? 563 : 119;
    final portStr = port == defaultPort ? '' : ':$port';
    return '$protocol://$host$portStr';
  }

  /// Whether authentication is configured.
  bool get hasCredentials =>
      username != null &&
      username!.isNotEmpty &&
      password != null &&
      password!.isNotEmpty;

  /// Create from JSON.
  factory NNTPAccount.fromJson(Map<String, dynamic> json) {
    return NNTPAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 119,
      useTLS: json['useTLS'] as bool? ?? false,
      username: json['username'] as String?,
      password: json['password'] as String?,
      isConnected: json['isConnected'] as bool? ?? false,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {},
      postingAllowed: json['postingAllowed'] as bool? ?? true,
      retentionDays: json['retentionDays'] as int?,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'useTLS': useTLS,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        'isConnected': isConnected,
        if (lastConnected != null)
          'lastConnected': lastConnected!.toIso8601String(),
        'capabilities': capabilities.toList(),
        'postingAllowed': postingAllowed,
        if (retentionDays != null) 'retentionDays': retentionDays,
      };

  /// Create a copy with modified fields.
  NNTPAccount copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    bool? useTLS,
    String? username,
    String? password,
    bool? isConnected,
    DateTime? lastConnected,
    Set<String>? capabilities,
    bool? postingAllowed,
    int? retentionDays,
  }) {
    return NNTPAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      useTLS: useTLS ?? this.useTLS,
      username: username ?? this.username,
      password: password ?? this.password,
      isConnected: isConnected ?? this.isConnected,
      lastConnected: lastConnected ?? this.lastConnected,
      capabilities: capabilities ?? this.capabilities,
      postingAllowed: postingAllowed ?? this.postingAllowed,
      retentionDays: retentionDays ?? this.retentionDays,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NNTPAccount && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NNTPAccount($name, $connectionString)';
}
