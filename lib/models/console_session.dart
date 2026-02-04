/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Model representing a console terminal session.
 */

/// State of a console session
enum ConsoleSessionState {
  stopped,
  running,
  suspended,
}

// Note: vmType, memory, networkEnabled, keepRunning, and mounts fields
// are kept for backward compatibility with existing session files but
// are no longer used for CLI terminal sessions.

/// Mount point configuration for VM filesystem access
class ConsoleMount {
  final String hostPath;
  final String vmPath;
  final bool readonly;

  const ConsoleMount({
    required this.hostPath,
    required this.vmPath,
    this.readonly = false,
  });

  Map<String, dynamic> toJson() => {
        'host_path': hostPath,
        'vm_path': vmPath,
        'readonly': readonly,
      };

  factory ConsoleMount.fromJson(Map<String, dynamic> json) {
    return ConsoleMount(
      hostPath: json['host_path'] as String? ?? '',
      vmPath: json['vm_path'] as String? ?? '',
      readonly: json['readonly'] as bool? ?? false,
    );
  }

  ConsoleMount copyWith({
    String? hostPath,
    String? vmPath,
    bool? readonly,
  }) {
    return ConsoleMount(
      hostPath: hostPath ?? this.hostPath,
      vmPath: vmPath ?? this.vmPath,
      readonly: readonly ?? this.readonly,
    );
  }
}

/// Model representing a console session
class ConsoleSession {
  final String id;
  final String name;
  final String created; // Format: YYYY-MM-DD HH:MM_ss
  final String author; // Callsign
  final String vmType; // alpine-x86, alpine-riscv64, buildroot-riscv64
  final int memory; // MB (64-512)
  final bool networkEnabled;
  final bool keepRunning;
  final ConsoleSessionState state;
  final String? description;
  final List<ConsoleMount> mounts;

  // Metadata
  final String? metadataNpub;
  final String? signature;

  // File paths
  final String? sessionPath; // Path to session folder
  final String? appPath; // Path to console app

  ConsoleSession({
    required this.id,
    required this.name,
    required this.created,
    required this.author,
    this.vmType = 'alpine-x86',
    this.memory = 128,
    this.networkEnabled = true,
    this.keepRunning = false,
    this.state = ConsoleSessionState.stopped,
    this.description,
    this.mounts = const [],
    this.metadataNpub,
    this.signature,
    this.sessionPath,
    this.appPath,
  });

  /// Parse created timestamp to DateTime
  DateTime get createdDateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get display timestamp
  String get displayCreated => created.replaceAll('_', ':');

  /// Check if session has a saved state
  bool get hasState => sessionPath != null;

  /// Get state file path
  String? get currentStatePath =>
      sessionPath != null ? '$sessionPath/current.state' : null;

  /// Get mounts file path
  String? get mountsPath =>
      sessionPath != null ? '$sessionPath/mounts.json' : null;

  /// Get session.txt file path
  String? get sessionFilePath =>
      sessionPath != null ? '$sessionPath/session.txt' : null;

  /// Get saved states folder path
  String? get savedStatesPath =>
      sessionPath != null ? '$sessionPath/saved' : null;

  /// Convert state enum to string
  String get stateString {
    switch (state) {
      case ConsoleSessionState.running:
        return 'running';
      case ConsoleSessionState.suspended:
        return 'suspended';
      case ConsoleSessionState.stopped:
      default:
        return 'stopped';
    }
  }

  /// Parse state string to enum
  static ConsoleSessionState parseState(String? state) {
    switch (state?.toLowerCase()) {
      case 'running':
        return ConsoleSessionState.running;
      case 'suspended':
        return ConsoleSessionState.suspended;
      case 'stopped':
      default:
        return ConsoleSessionState.stopped;
    }
  }

  /// Convert to session.txt content
  String toSessionTxt() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('# SESSION: $name');
    buffer.writeln();
    buffer.writeln('CREATED: $created');
    buffer.writeln('AUTHOR: $author');
    buffer.writeln('VM_TYPE: $vmType');
    buffer.writeln('MEMORY: $memory');
    buffer.writeln('NETWORK: ${networkEnabled ? 'enabled' : 'disabled'}');
    buffer.writeln('KEEP_RUNNING: $keepRunning');
    buffer.writeln('STATUS: $stateString');

    // Description
    if (description != null && description!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(description);
    }

    // Metadata
    if (metadataNpub != null) {
      buffer.writeln();
      buffer.writeln('--> npub: $metadataNpub');
    }
    if (signature != null) {
      if (metadataNpub == null) buffer.writeln();
      buffer.writeln('--> signature: $signature');
    }

    return buffer.toString();
  }

  /// Convert mounts to JSON
  Map<String, dynamic> mountsToJson() => {
        'mounts': mounts.map((m) => m.toJson()).toList(),
      };

  /// Create copy with modifications
  ConsoleSession copyWith({
    String? id,
    String? name,
    String? created,
    String? author,
    String? vmType,
    int? memory,
    bool? networkEnabled,
    bool? keepRunning,
    ConsoleSessionState? state,
    String? description,
    List<ConsoleMount>? mounts,
    String? metadataNpub,
    String? signature,
    String? sessionPath,
    String? appPath,
  }) {
    return ConsoleSession(
      id: id ?? this.id,
      name: name ?? this.name,
      created: created ?? this.created,
      author: author ?? this.author,
      vmType: vmType ?? this.vmType,
      memory: memory ?? this.memory,
      networkEnabled: networkEnabled ?? this.networkEnabled,
      keepRunning: keepRunning ?? this.keepRunning,
      state: state ?? this.state,
      description: description ?? this.description,
      mounts: mounts ?? this.mounts,
      metadataNpub: metadataNpub ?? this.metadataNpub,
      signature: signature ?? this.signature,
      sessionPath: sessionPath ?? this.sessionPath,
      appPath: appPath ?? this.appPath,
    );
  }

  @override
  String toString() =>
      'ConsoleSession($id, $name, $vmType, ${memory}MB, $stateString)';
}
