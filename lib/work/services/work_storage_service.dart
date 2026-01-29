/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../services/log_service.dart';
import '../models/workspace.dart';
import '../models/ndf_document.dart';
import 'ndf_service.dart';

/// Service for managing workspace storage
class WorkStorageService {
  final String basePath;

  WorkStorageService(this.basePath);

  /// Get the workspaces directory
  String get workspacesPath => '$basePath/workspaces';

  /// Get the path for a specific workspace
  String workspacePath(String workspaceId) => '$workspacesPath/$workspaceId';

  /// Get the workspace.json path for a workspace
  String workspaceConfigPath(String workspaceId) =>
      '${workspacePath(workspaceId)}/workspace.json';

  /// Initialize the storage directory structure
  Future<void> initialize() async {
    final dir = Directory(workspacesPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      LogService().log('WorkStorageService: Created workspaces directory');
    }
  }

  /// Load all workspaces
  Future<List<Workspace>> loadWorkspaces() async {
    final workspaces = <Workspace>[];
    final dir = Directory(workspacesPath);

    if (!await dir.exists()) {
      return workspaces;
    }

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        try {
          final workspace = await loadWorkspace(entity.path.split('/').last);
          if (workspace != null) {
            workspaces.add(workspace);
          }
        } catch (e) {
          LogService().log('WorkStorageService: Error loading workspace ${entity.path}: $e');
        }
      }
    }

    // Sort by modified date (newest first)
    workspaces.sort((a, b) => b.modified.compareTo(a.modified));
    return workspaces;
  }

  /// Load a specific workspace by ID
  Future<Workspace?> loadWorkspace(String workspaceId) async {
    final configPath = workspaceConfigPath(workspaceId);
    final file = File(configPath);

    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Workspace.fromJson(json);
    } catch (e) {
      LogService().log('WorkStorageService: Error parsing workspace $workspaceId: $e');
      return null;
    }
  }

  /// Save a workspace
  Future<void> saveWorkspace(Workspace workspace) async {
    final wsPath = workspacePath(workspace.id);
    final dir = Directory(wsPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final configFile = File(workspaceConfigPath(workspace.id));
    await configFile.writeAsString(workspace.toJsonString());
    LogService().log('WorkStorageService: Saved workspace ${workspace.id}');
  }

  /// Create a new workspace
  Future<Workspace> createWorkspace({
    required String name,
    required String ownerNpub,
    String? description,
  }) async {
    final workspace = Workspace.create(
      name: name,
      ownerNpub: ownerNpub,
      description: description,
    );

    await saveWorkspace(workspace);
    return workspace;
  }

  /// Delete a workspace
  Future<void> deleteWorkspace(String workspaceId) async {
    final dir = Directory(workspacePath(workspaceId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      LogService().log('WorkStorageService: Deleted workspace $workspaceId');
    }
  }

  /// List all NDF documents in a workspace
  Future<List<NdfDocumentRef>> listDocuments(String workspaceId) async {
    final documents = <NdfDocumentRef>[];
    final wsPath = workspacePath(workspaceId);
    final dir = Directory(wsPath);

    if (!await dir.exists()) {
      return documents;
    }

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.ndf')) {
        try {
          final ref = await _readDocumentRef(entity);
          if (ref != null) {
            documents.add(ref);
          }
        } catch (e) {
          LogService().log('WorkStorageService: Error reading NDF ${entity.path}: $e');
        }
      }
    }

    // Sort by modified date (newest first)
    documents.sort((a, b) => b.modified.compareTo(a.modified));
    return documents;
  }

  /// Read NDF document metadata from the archive
  Future<NdfDocumentRef?> _readDocumentRef(File ndfFile) async {
    final filename = ndfFile.path.split('/').last;

    // Read actual metadata from NDF archive
    final ndfService = NdfService();
    final metadata = await ndfService.readMetadata(ndfFile.path);

    if (metadata != null) {
      return NdfDocumentRef(
        filename: filename,
        type: metadata.type,
        title: metadata.title,
        description: metadata.description,
        logo: metadata.logo,
        thumbnail: metadata.thumbnail,
        modified: metadata.modified,
        fileSize: (await ndfFile.stat()).size,
      );
    }

    // Fallback if metadata cannot be read
    final stat = await ndfFile.stat();
    final basename = filename.replaceAll('.ndf', '');
    return NdfDocumentRef(
      filename: filename,
      type: NdfDocumentType.document,
      title: basename.replaceAll('-', ' ').replaceAll('_', ' '),
      modified: stat.modified,
      fileSize: stat.size,
    );
  }

  /// Get the path for the workspace logo file
  String? workspaceLogoPath(String workspaceId, String? logoFilename) {
    if (logoFilename == null) return null;
    return '${workspacePath(workspaceId)}/$logoFilename';
  }

  /// Read the workspace logo bytes
  Future<Uint8List?> readWorkspaceLogo(String workspaceId) async {
    final workspace = await loadWorkspace(workspaceId);
    if (workspace?.logo == null) return null;

    final logoPath = workspaceLogoPath(workspaceId, workspace!.logo);
    if (logoPath == null) return null;

    final file = File(logoPath);
    if (!await file.exists()) return null;

    return file.readAsBytes();
  }

  /// Save a workspace logo
  Future<String> saveWorkspaceLogo(String workspaceId, Uint8List logoBytes, String extension) async {
    final filename = 'logo.$extension';
    final logoPath = '${workspacePath(workspaceId)}/$filename';
    final file = File(logoPath);
    await file.writeAsBytes(logoBytes);

    // Update workspace with logo filename
    final workspace = await loadWorkspace(workspaceId);
    if (workspace != null) {
      workspace.logo = filename;
      workspace.touch();
      await saveWorkspace(workspace);
    }

    LogService().log('WorkStorageService: Saved workspace logo $filename');
    return filename;
  }

  /// Delete the workspace logo
  Future<void> deleteWorkspaceLogo(String workspaceId) async {
    final workspace = await loadWorkspace(workspaceId);
    if (workspace?.logo == null) return;

    final logoPath = workspaceLogoPath(workspaceId, workspace!.logo);
    if (logoPath != null) {
      final file = File(logoPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    workspace.logo = null;
    workspace.touch();
    await saveWorkspace(workspace);

    LogService().log('WorkStorageService: Deleted workspace logo');
  }

  /// Get the full path for an NDF document in a workspace
  String documentPath(String workspaceId, String filename) =>
      '${workspacePath(workspaceId)}/$filename';

  /// Delete an NDF document
  Future<void> deleteDocument(String workspaceId, String filename) async {
    final file = File(documentPath(workspaceId, filename));
    if (await file.exists()) {
      await file.delete();
      LogService().log('WorkStorageService: Deleted document $filename from $workspaceId');

      // Update workspace to remove document reference
      final workspace = await loadWorkspace(workspaceId);
      if (workspace != null) {
        workspace.removeDocument(filename);
        await saveWorkspace(workspace);
      }
    }
  }
}
