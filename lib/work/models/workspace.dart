/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

/// Collaborator role in a workspace
enum CollaboratorRole {
  editor,
  viewer,
}

/// A collaborator in a workspace
class WorkspaceCollaborator {
  final String npub;
  final CollaboratorRole role;
  final DateTime added;
  final String? name;
  final String? callsign;

  WorkspaceCollaborator({
    required this.npub,
    required this.role,
    required this.added,
    this.name,
    this.callsign,
  });

  factory WorkspaceCollaborator.fromJson(Map<String, dynamic> json) {
    return WorkspaceCollaborator(
      npub: json['npub'] as String,
      role: CollaboratorRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => CollaboratorRole.viewer,
      ),
      added: DateTime.parse(json['added'] as String),
      name: json['name'] as String?,
      callsign: json['callsign'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'npub': npub,
    'role': role.name,
    'added': added.toIso8601String(),
    if (name != null) 'name': name,
    if (callsign != null) 'callsign': callsign,
  };
}

/// A folder within a workspace
class WorkspaceFolder {
  final String id;
  String name;
  final String? parentId;
  final DateTime created;
  DateTime modified;

  WorkspaceFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.created,
    required this.modified,
  });

  factory WorkspaceFolder.create({
    required String name,
    String? parentId,
  }) {
    final now = DateTime.now();
    final id = 'folder-${now.millisecondsSinceEpoch.toRadixString(36)}';
    return WorkspaceFolder(
      id: id,
      name: name,
      parentId: parentId,
      created: now,
      modified: now,
    );
  }

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) {
    return WorkspaceFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parent_id'] as String?,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (parentId != null) 'parent_id': parentId,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
  };
}

/// A workspace containing NDF documents and folders
class Workspace {
  final String id;
  String name;
  String? description;
  final DateTime created;
  DateTime modified;
  final String ownerNpub;
  final List<WorkspaceCollaborator> collaborators;
  final List<String> documents;
  final List<WorkspaceFolder> folders;
  final Map<String, String?> documentFolders; // document filename -> folder id (null = root)

  Workspace({
    required this.id,
    required this.name,
    this.description,
    required this.created,
    required this.modified,
    required this.ownerNpub,
    List<WorkspaceCollaborator>? collaborators,
    List<String>? documents,
    List<WorkspaceFolder>? folders,
    Map<String, String?>? documentFolders,
  }) : collaborators = collaborators ?? [],
       documents = documents ?? [],
       folders = folders ?? [],
       documentFolders = documentFolders ?? {};

  factory Workspace.create({
    required String name,
    required String ownerNpub,
    String? description,
  }) {
    final now = DateTime.now();
    final id = _generateId(name);
    return Workspace(
      id: id,
      name: name,
      description: description,
      created: now,
      modified: now,
      ownerNpub: ownerNpub,
    );
  }

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final docFoldersJson = json['document_folders'] as Map<String, dynamic>?;
    final docFolders = <String, String?>{};
    if (docFoldersJson != null) {
      for (final entry in docFoldersJson.entries) {
        docFolders[entry.key] = entry.value as String?;
      }
    }

    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
      ownerNpub: json['owner_npub'] as String,
      collaborators: (json['collaborators'] as List<dynamic>?)
          ?.map((c) => WorkspaceCollaborator.fromJson(c as Map<String, dynamic>))
          .toList() ?? [],
      documents: (json['documents'] as List<dynamic>?)
          ?.map((d) => d as String)
          .toList() ?? [],
      folders: (json['folders'] as List<dynamic>?)
          ?.map((f) => WorkspaceFolder.fromJson(f as Map<String, dynamic>))
          .toList() ?? [],
      documentFolders: docFolders,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'owner_npub': ownerNpub,
    'collaborators': collaborators.map((c) => c.toJson()).toList(),
    'documents': documents,
    'folders': folders.map((f) => f.toJson()).toList(),
    'document_folders': documentFolders,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Touch the modified timestamp
  void touch() {
    modified = DateTime.now();
  }

  /// Add a collaborator
  void addCollaborator(WorkspaceCollaborator collaborator) {
    collaborators.removeWhere((c) => c.npub == collaborator.npub);
    collaborators.add(collaborator);
    touch();
  }

  /// Remove a collaborator
  void removeCollaborator(String npub) {
    collaborators.removeWhere((c) => c.npub == npub);
    touch();
  }

  /// Add a document filename to a folder (null = root)
  void addDocument(String filename, {String? folderId}) {
    if (!documents.contains(filename)) {
      documents.add(filename);
    }
    documentFolders[filename] = folderId;
    touch();
  }

  /// Remove a document filename
  void removeDocument(String filename) {
    documents.remove(filename);
    documentFolders.remove(filename);
    touch();
  }

  /// Add a folder
  void addFolder(WorkspaceFolder folder) {
    folders.add(folder);
    touch();
  }

  /// Remove a folder and move its contents to parent
  void removeFolder(String folderId) {
    final folder = folders.where((f) => f.id == folderId).firstOrNull;
    if (folder == null) return;

    // Move documents in this folder to parent
    for (final entry in documentFolders.entries.toList()) {
      if (entry.value == folderId) {
        documentFolders[entry.key] = folder.parentId;
      }
    }

    // Move subfolders to parent
    for (final subfolder in folders.where((f) => f.parentId == folderId)) {
      folders[folders.indexOf(subfolder)] = WorkspaceFolder(
        id: subfolder.id,
        name: subfolder.name,
        parentId: folder.parentId,
        created: subfolder.created,
        modified: DateTime.now(),
      );
    }

    folders.removeWhere((f) => f.id == folderId);
    touch();
  }

  /// Get folders in a specific parent (null = root)
  List<WorkspaceFolder> getFoldersIn(String? parentId) {
    return folders.where((f) => f.parentId == parentId).toList();
  }

  /// Get documents in a specific folder (null = root)
  List<String> getDocumentsIn(String? folderId) {
    return documents.where((d) => documentFolders[d] == folderId).toList();
  }

  /// Move document to folder
  void moveDocument(String filename, String? toFolderId) {
    if (documents.contains(filename)) {
      documentFolders[filename] = toFolderId;
      touch();
    }
  }

  /// Generate a URL-safe ID from name
  static String _generateId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '$slug-$timestamp';
  }
}
