/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Access control types for NDF permissions
enum NdfAccessType {
  public,
  ownersOnly,
  allowlist,
  denylist,
  delegated,
  none,
}

/// Permission actions in NDF documents
enum NdfPermissionAction {
  view,
  comment,
  react,
  edit,
  formSubmit,
  admin,
}

/// Owner role in an NDF document
enum NdfOwnerRole {
  creator,
  coOwner,
  admin,
}

/// An owner of an NDF document
class NdfOwner {
  final String npub;
  final String? name;
  final String? callsign;
  final NdfOwnerRole role;
  final int addedAt;
  final String? addedBy;

  NdfOwner({
    required this.npub,
    this.name,
    this.callsign,
    required this.role,
    required this.addedAt,
    this.addedBy,
  });

  factory NdfOwner.fromJson(Map<String, dynamic> json) {
    return NdfOwner(
      npub: json['npub'] as String,
      name: json['name'] as String?,
      callsign: json['callsign'] as String?,
      role: NdfOwnerRole.values.firstWhere(
        (r) => r.name == _snakeToCamel(json['role'] as String),
        orElse: () => NdfOwnerRole.admin,
      ),
      addedAt: json['added_at'] as int,
      addedBy: json['added_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'npub': npub,
    if (name != null) 'name': name,
    if (callsign != null) 'callsign': callsign,
    'role': _camelToSnake(role.name),
    'added_at': addedAt,
    'added_by': addedBy,
  };
}

/// Access control entry
class NdfAccess {
  final NdfAccessType type;
  final List<String>? npubs;

  NdfAccess({
    required this.type,
    this.npubs,
  });

  factory NdfAccess.fromJson(Map<String, dynamic> json) {
    return NdfAccess(
      type: NdfAccessType.values.firstWhere(
        (t) => t.name == _snakeToCamel(json['type'] as String),
        orElse: () => NdfAccessType.none,
      ),
      npubs: (json['npubs'] as List<dynamic>?)
          ?.map((n) => n as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': _camelToSnake(type.name),
    if (npubs != null) 'npubs': npubs,
  };
}

/// Signature entry
class NdfSignature {
  final String npub;
  final int createdAt;
  final int kind;
  final String contentHash;
  final String sig;

  NdfSignature({
    required this.npub,
    required this.createdAt,
    required this.kind,
    required this.contentHash,
    required this.sig,
  });

  factory NdfSignature.fromJson(Map<String, dynamic> json) {
    return NdfSignature(
      npub: json['npub'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      contentHash: json['content_hash'] as String,
      sig: json['sig'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'npub': npub,
    'created_at': createdAt,
    'kind': kind,
    'content_hash': contentHash,
    'sig': sig,
  };
}

/// NDF permissions structure (from permissions.json)
class NdfPermission {
  static const String schema = 'ndf-permissions-1.0';
  static const int permissionsSignatureKind = 1115;

  final String documentId;
  final List<NdfOwner> owners;
  final Map<NdfPermissionAction, NdfAccess> access;
  final bool allowAnonymousView;
  final bool allowAnonymousComment;
  final bool requireSignatureForChanges;
  final bool requireSignatureForComments;
  final bool requireSignatureForReactions;
  final bool requireSignatureForFormSubmit;
  final int? maxFileSizeMb;
  final List<String>? allowedAssetTypes;
  final DateTime? expiry;
  final bool revoked;
  final List<NdfSignature> signatures;

  NdfPermission({
    required this.documentId,
    required this.owners,
    Map<NdfPermissionAction, NdfAccess>? access,
    this.allowAnonymousView = true,
    this.allowAnonymousComment = false,
    this.requireSignatureForChanges = true,
    this.requireSignatureForComments = true,
    this.requireSignatureForReactions = true,
    this.requireSignatureForFormSubmit = true,
    this.maxFileSizeMb = 50,
    this.allowedAssetTypes,
    this.expiry,
    this.revoked = false,
    List<NdfSignature>? signatures,
  }) : access = access ?? _defaultAccess(),
       signatures = signatures ?? [];

  /// Create default permissions for a new document
  factory NdfPermission.create({
    required String documentId,
    required String ownerNpub,
    String? ownerName,
    String? ownerCallsign,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return NdfPermission(
      documentId: documentId,
      owners: [
        NdfOwner(
          npub: ownerNpub,
          name: ownerName,
          callsign: ownerCallsign,
          role: NdfOwnerRole.creator,
          addedAt: now,
          addedBy: null,
        ),
      ],
    );
  }

  factory NdfPermission.fromJson(Map<String, dynamic> json) {
    final accessJson = json['access'] as Map<String, dynamic>?;
    final access = <NdfPermissionAction, NdfAccess>{};
    if (accessJson != null) {
      for (final entry in accessJson.entries) {
        final action = NdfPermissionAction.values.firstWhere(
          (a) => a.name == _snakeToCamel(entry.key),
          orElse: () => NdfPermissionAction.view,
        );
        access[action] = NdfAccess.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    final restrictions = json['restrictions'] as Map<String, dynamic>? ?? {};

    return NdfPermission(
      documentId: json['document_id'] as String,
      owners: (json['owners'] as List<dynamic>)
          .map((o) => NdfOwner.fromJson(o as Map<String, dynamic>))
          .toList(),
      access: access.isEmpty ? _defaultAccess() : access,
      allowAnonymousView: restrictions['allow_anonymous_view'] as bool? ?? true,
      allowAnonymousComment: restrictions['allow_anonymous_comment'] as bool? ?? false,
      requireSignatureForChanges: restrictions['require_signature_for_changes'] as bool? ?? true,
      requireSignatureForComments: restrictions['require_signature_for_comments'] as bool? ?? true,
      requireSignatureForReactions: restrictions['require_signature_for_reactions'] as bool? ?? true,
      requireSignatureForFormSubmit: restrictions['require_signature_for_form_submit'] as bool? ?? true,
      maxFileSizeMb: restrictions['max_file_size_mb'] as int?,
      allowedAssetTypes: (restrictions['allowed_asset_types'] as List<dynamic>?)
          ?.map((t) => t as String)
          .toList(),
      expiry: restrictions['expiry'] != null
          ? DateTime.parse(restrictions['expiry'] as String)
          : null,
      revoked: restrictions['revoked'] as bool? ?? false,
      signatures: (json['signatures'] as List<dynamic>?)
          ?.map((s) => NdfSignature.fromJson(s as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'document_id': documentId,
    'owners': owners.map((o) => o.toJson()).toList(),
    'access': {
      for (final entry in access.entries)
        _camelToSnake(entry.key.name): entry.value.toJson(),
    },
    'restrictions': {
      'allow_anonymous_view': allowAnonymousView,
      'allow_anonymous_comment': allowAnonymousComment,
      'require_signature_for_changes': requireSignatureForChanges,
      'require_signature_for_comments': requireSignatureForComments,
      'require_signature_for_reactions': requireSignatureForReactions,
      'require_signature_for_form_submit': requireSignatureForFormSubmit,
      if (maxFileSizeMb != null) 'max_file_size_mb': maxFileSizeMb,
      if (allowedAssetTypes != null) 'allowed_asset_types': allowedAssetTypes,
      if (expiry != null) 'expiry': expiry!.toIso8601String(),
      'revoked': revoked,
    },
    'signatures': signatures.map((s) => s.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Check if an npub has a specific permission
  bool hasPermission(String npub, NdfPermissionAction action) {
    // Check if user is an owner
    if (owners.any((o) => o.npub == npub)) {
      return true;
    }

    final accessEntry = access[action];
    if (accessEntry == null) return false;

    switch (accessEntry.type) {
      case NdfAccessType.public:
        return true;
      case NdfAccessType.ownersOnly:
        return owners.any((o) => o.npub == npub);
      case NdfAccessType.allowlist:
        return accessEntry.npubs?.contains(npub) ?? false;
      case NdfAccessType.denylist:
        return !(accessEntry.npubs?.contains(npub) ?? false);
      case NdfAccessType.delegated:
        // TODO: implement delegation chain verification
        return false;
      case NdfAccessType.none:
        return false;
    }
  }

  static Map<NdfPermissionAction, NdfAccess> _defaultAccess() => {
    NdfPermissionAction.view: NdfAccess(type: NdfAccessType.public),
    NdfPermissionAction.comment: NdfAccess(type: NdfAccessType.public),
    NdfPermissionAction.react: NdfAccess(type: NdfAccessType.public),
    NdfPermissionAction.edit: NdfAccess(type: NdfAccessType.ownersOnly),
    NdfPermissionAction.formSubmit: NdfAccess(type: NdfAccessType.public),
    NdfPermissionAction.admin: NdfAccess(type: NdfAccessType.ownersOnly),
  };
}

/// Convert snake_case to camelCase
String _snakeToCamel(String snake) {
  final parts = snake.split('_');
  if (parts.length == 1) return snake;
  return parts.first + parts.skip(1).map((p) =>
    p.isNotEmpty ? p[0].toUpperCase() + p.substring(1) : '').join();
}

/// Convert camelCase to snake_case
String _camelToSnake(String camel) {
  return camel.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}
