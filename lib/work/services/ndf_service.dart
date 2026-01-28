/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../services/log_service.dart';
import '../models/ndf_document.dart';
import '../models/ndf_permission.dart';
import '../models/spreadsheet_content.dart';
import '../models/document_content.dart';
import '../models/form_content.dart';

/// Service for reading and writing NDF (Nostr Data Format) documents
class NdfService {
  /// Read NDF metadata from a file
  Future<NdfDocument?> readMetadata(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find ndf.json in archive
      for (final entry in archive) {
        if (entry.name == 'ndf.json' && entry.isFile) {
          final content = utf8.decode(entry.content as List<int>);
          final json = jsonDecode(content) as Map<String, dynamic>;
          return NdfDocument.fromJson(json);
        }
      }

      LogService().log('NdfService: ndf.json not found in $filePath');
      return null;
    } catch (e) {
      LogService().log('NdfService: Error reading NDF metadata from $filePath: $e');
      return null;
    }
  }

  /// Read NDF permissions from a file
  Future<NdfPermission?> readPermissions(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find permissions.json in archive
      for (final entry in archive) {
        if (entry.name == 'permissions.json' && entry.isFile) {
          final content = utf8.decode(entry.content as List<int>);
          final json = jsonDecode(content) as Map<String, dynamic>;
          return NdfPermission.fromJson(json);
        }
      }

      LogService().log('NdfService: permissions.json not found in $filePath');
      return null;
    } catch (e) {
      LogService().log('NdfService: Error reading NDF permissions from $filePath: $e');
      return null;
    }
  }

  /// Read a specific file from an NDF archive
  Future<Uint8List?> readArchiveFile(String filePath, String archivePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final entry in archive) {
        if (entry.name == archivePath && entry.isFile) {
          return Uint8List.fromList(entry.content as List<int>);
        }
      }

      return null;
    } catch (e) {
      LogService().log('NdfService: Error reading $archivePath from $filePath: $e');
      return null;
    }
  }

  /// Read JSON content from an NDF archive
  Future<Map<String, dynamic>?> readArchiveJson(String filePath, String archivePath) async {
    final bytes = await readArchiveFile(filePath, archivePath);
    if (bytes == null) return null;

    try {
      final content = utf8.decode(bytes);
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      LogService().log('NdfService: Error parsing JSON from $archivePath: $e');
      return null;
    }
  }

  /// Create a new NDF document
  Future<String> createDocument({
    required String outputPath,
    required NdfDocument metadata,
    required NdfPermission permissions,
    Map<String, dynamic>? mainContent,
  }) async {
    final archive = Archive();

    // Add ndf.json
    final ndfJson = utf8.encode(metadata.toJsonString());
    archive.addFile(ArchiveFile('ndf.json', ndfJson.length, ndfJson));

    // Add permissions.json
    final permissionsJson = utf8.encode(permissions.toJsonString());
    archive.addFile(ArchiveFile('permissions.json', permissionsJson.length, permissionsJson));

    // Add content/main.json if provided
    if (mainContent != null) {
      final mainJson = utf8.encode(const JsonEncoder.withIndent('  ').convert(mainContent));
      archive.addFile(ArchiveFile('content/main.json', mainJson.length, mainJson));
    }

    // Create default content based on document type
    if (mainContent == null) {
      final defaultContent = _createDefaultContent(metadata.type);
      final contentJson = utf8.encode(const JsonEncoder.withIndent('  ').convert(defaultContent));
      archive.addFile(ArchiveFile('content/main.json', contentJson.length, contentJson));
    }

    // Create empty directories structure
    _addEmptyDirectories(archive);

    // Write the ZIP file
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to encode NDF archive');
    }

    final file = File(outputPath);
    await file.writeAsBytes(zipData);

    LogService().log('NdfService: Created NDF document at $outputPath');
    return outputPath;
  }

  /// Add empty directory placeholders
  /// Note: ZIP archives don't support truly empty directories.
  /// Directory structure is created implicitly by file paths in the archive.
  void _addEmptyDirectories(Archive archive) {
    // This method is intentionally a no-op.
    // In the future, we could add .gitkeep-like placeholder files
    // if we need to preserve empty directory structure.
  }

  /// Create default content based on document type
  Map<String, dynamic> _createDefaultContent(NdfDocumentType type) {
    switch (type) {
      case NdfDocumentType.spreadsheet:
        return {
          'type': 'spreadsheet',
          'active_sheet': 'sheet-001',
          'sheets': ['sheet-001'],
          'named_ranges': {},
          'global_styles': {
            'default': {
              'font': {'family': 'sans-serif', 'size': 11},
              'alignment': {'h': 'left', 'v': 'middle'},
            },
          },
        };

      case NdfDocumentType.document:
        return {
          'type': 'document',
          'schema': 'ndf-richtext-1.0',
          'content': [
            {
              'type': 'heading',
              'level': 1,
              'id': 'h-001',
              'content': [{'type': 'text', 'value': 'Untitled Document'}],
            },
            {
              'type': 'paragraph',
              'id': 'p-001',
              'content': [{'type': 'text', 'value': ''}],
            },
          ],
          'styles': {
            'page': {
              'size': 'A4',
              'margins': {'top': 72, 'bottom': 72, 'left': 72, 'right': 72},
            },
          },
        };

      case NdfDocumentType.presentation:
        return {
          'type': 'presentation',
          'schema': 'ndf-slides-1.0',
          'aspect_ratio': '16:9',
          'dimensions': {'width': 1920, 'height': 1080},
          'slides': ['slide-001'],
          'theme': {
            'colors': {
              'primary': '#1E3A5F',
              'secondary': '#4A90D9',
              'accent': '#F5A623',
              'background': '#FFFFFF',
              'text': '#333333',
            },
            'fonts': {
              'heading': {'family': 'sans-serif', 'weight': 700},
              'body': {'family': 'sans-serif', 'weight': 400},
            },
          },
          'transitions': {
            'default': {'type': 'fade', 'duration': 300},
          },
        };

      case NdfDocumentType.form:
        return {
          'type': 'form',
          'schema': 'ndf-form-1.0',
          'title': 'Untitled Form',
          'description': '',
          'version': 1,
          'settings': {
            'allow_anonymous': false,
            'require_signature': true,
            'multiple_submissions': false,
            'editable_after_submit': false,
          },
          'fields': [],
          'layout': {
            'type': 'linear',
          },
        };
    }
  }

  /// Update NDF metadata in an existing file
  Future<void> updateMetadata(String filePath, NdfDocument metadata) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('NDF file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Create new archive with updated metadata
    final newArchive = Archive();

    for (final entry in archive) {
      if (entry.name == 'ndf.json') {
        // Replace with new metadata
        final ndfJson = utf8.encode(metadata.toJsonString());
        newArchive.addFile(ArchiveFile('ndf.json', ndfJson.length, ndfJson));
      } else {
        // Copy existing entry
        newArchive.addFile(entry);
      }
    }

    // Write updated archive
    final zipData = ZipEncoder().encode(newArchive);
    if (zipData == null) {
      throw Exception('Failed to encode updated NDF archive');
    }

    await file.writeAsBytes(zipData);
    LogService().log('NdfService: Updated metadata in $filePath');
  }

  /// List all files in an NDF archive
  Future<List<String>> listArchiveFiles(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      return archive.map((e) => e.name).toList();
    } catch (e) {
      LogService().log('NdfService: Error listing archive files from $filePath: $e');
      return [];
    }
  }

  // ============================================================
  // SPREADSHEET CONTENT METHODS
  // ============================================================

  /// Read spreadsheet main content
  Future<SpreadsheetContent?> readSpreadsheetContent(String filePath) async {
    final json = await readArchiveJson(filePath, 'content/main.json');
    if (json == null) return null;
    try {
      return SpreadsheetContent.fromJson(json);
    } catch (e) {
      LogService().log('NdfService: Error parsing spreadsheet content: $e');
      return null;
    }
  }

  /// Read a spreadsheet sheet
  Future<SpreadsheetSheet?> readSheet(String filePath, String sheetId) async {
    final json = await readArchiveJson(filePath, 'content/$sheetId.json');
    if (json == null) return null;
    try {
      return SpreadsheetSheet.fromJson(json);
    } catch (e) {
      LogService().log('NdfService: Error parsing sheet $sheetId: $e');
      return null;
    }
  }

  /// Save spreadsheet content and sheets
  Future<void> saveSpreadsheet(
    String filePath,
    SpreadsheetContent content,
    Map<String, SpreadsheetSheet> sheets,
  ) async {
    await _updateArchiveFiles(filePath, {
      'content/main.json': content.toJsonString(),
      for (final entry in sheets.entries)
        'content/${entry.key}.json': entry.value.toJsonString(),
    });
  }

  /// Save a single sheet
  Future<void> saveSheet(
    String filePath,
    SpreadsheetSheet sheet,
  ) async {
    await _updateArchiveFiles(filePath, {
      'content/${sheet.id}.json': sheet.toJsonString(),
    });
  }

  // ============================================================
  // DOCUMENT CONTENT METHODS
  // ============================================================

  /// Read document content
  Future<DocumentContent?> readDocumentContent(String filePath) async {
    final json = await readArchiveJson(filePath, 'content/main.json');
    if (json == null) return null;
    try {
      return DocumentContent.fromJson(json);
    } catch (e) {
      LogService().log('NdfService: Error parsing document content: $e');
      return null;
    }
  }

  /// Save document content
  Future<void> saveDocumentContent(
    String filePath,
    DocumentContent content,
  ) async {
    await _updateArchiveFiles(filePath, {
      'content/main.json': content.toJsonString(),
    });
  }

  // ============================================================
  // FORM CONTENT METHODS
  // ============================================================

  /// Read form content
  Future<FormContent?> readFormContent(String filePath) async {
    final json = await readArchiveJson(filePath, 'content/main.json');
    if (json == null) return null;
    try {
      return FormContent.fromJson(json);
    } catch (e) {
      LogService().log('NdfService: Error parsing form content: $e');
      return null;
    }
  }

  /// Save form content
  Future<void> saveFormContent(
    String filePath,
    FormContent content,
  ) async {
    await _updateArchiveFiles(filePath, {
      'content/main.json': content.toJsonString(),
    });
  }

  /// Read form responses
  Future<List<FormResponse>> readFormResponses(String filePath) async {
    final files = await listArchiveFiles(filePath);
    final responses = <FormResponse>[];

    for (final file in files) {
      if (file.startsWith('social/responses/') && file.endsWith('.json')) {
        final json = await readArchiveJson(filePath, file);
        if (json != null) {
          try {
            responses.add(FormResponse.fromJson(json));
          } catch (e) {
            LogService().log('NdfService: Error parsing response $file: $e');
          }
        }
      }
    }

    // Sort by submission date (newest first)
    responses.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return responses;
  }

  /// Save a form response
  Future<void> saveFormResponse(
    String filePath,
    FormResponse response,
  ) async {
    await _updateArchiveFiles(filePath, {
      'social/responses/${response.id}.json': response.toJsonString(),
    });
  }

  // ============================================================
  // ASSET METHODS
  // ============================================================

  /// Read an asset from the archive
  Future<Uint8List?> readAsset(String filePath, String assetPath) async {
    // assetPath should be like "images/photo.jpg"
    return readArchiveFile(filePath, 'assets/$assetPath');
  }

  /// Save an asset to the archive
  Future<void> saveAsset(
    String filePath,
    String assetPath,
    Uint8List data,
  ) async {
    await _updateArchiveFilesBytes(filePath, {
      'assets/$assetPath': data,
    });
  }

  /// List all assets in the archive
  Future<List<String>> listAssets(String filePath) async {
    final files = await listArchiveFiles(filePath);
    return files
        .where((f) => f.startsWith('assets/') && !f.endsWith('/'))
        .map((f) => f.substring(7)) // Remove 'assets/' prefix
        .toList();
  }

  /// Extract an asset to a temporary file and return its path
  Future<String?> extractAssetToTemp(
    String filePath,
    String assetPath,
  ) async {
    final data = await readAsset(filePath, assetPath);
    if (data == null) return null;

    final tempDir = Directory.systemTemp;
    final ext = assetPath.split('.').last;
    final tempFile = File(
      '${tempDir.path}/ndf_asset_${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    await tempFile.writeAsBytes(data);
    return tempFile.path;
  }

  // ============================================================
  // PRIVATE HELPER METHODS
  // ============================================================

  /// Update multiple text files in an archive
  Future<void> _updateArchiveFiles(
    String filePath,
    Map<String, String> files,
  ) async {
    final bytesMap = <String, Uint8List>{};
    for (final entry in files.entries) {
      bytesMap[entry.key] = Uint8List.fromList(utf8.encode(entry.value));
    }
    await _updateArchiveFilesBytes(filePath, bytesMap);
  }

  /// Update multiple binary files in an archive
  Future<void> _updateArchiveFilesBytes(
    String filePath,
    Map<String, Uint8List> files,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('NDF file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Create new archive
    final newArchive = Archive();
    final addedPaths = <String>{};

    // Copy existing entries, replacing those in files map
    for (final entry in archive) {
      if (files.containsKey(entry.name)) {
        // Replace with new content
        final newData = files[entry.name]!;
        newArchive.addFile(ArchiveFile(entry.name, newData.length, newData));
        addedPaths.add(entry.name);
      } else {
        // Copy existing entry
        newArchive.addFile(entry);
      }
    }

    // Add new files that didn't exist before
    for (final entry in files.entries) {
      if (!addedPaths.contains(entry.key)) {
        newArchive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
    }

    // Write updated archive
    final zipData = ZipEncoder().encode(newArchive);
    if (zipData == null) {
      throw Exception('Failed to encode updated NDF archive');
    }

    await file.writeAsBytes(zipData);
    LogService().log('NdfService: Updated ${files.length} files in $filePath');
  }

  /// Delete files from an archive
  Future<void> deleteArchiveFiles(
    String filePath,
    List<String> paths,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('NDF file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Create new archive without deleted files
    final newArchive = Archive();
    final pathSet = paths.toSet();

    for (final entry in archive) {
      if (!pathSet.contains(entry.name)) {
        newArchive.addFile(entry);
      }
    }

    // Write updated archive
    final zipData = ZipEncoder().encode(newArchive);
    if (zipData == null) {
      throw Exception('Failed to encode updated NDF archive');
    }

    await file.writeAsBytes(zipData);
    LogService().log('NdfService: Deleted ${paths.length} files from $filePath');
  }
}
