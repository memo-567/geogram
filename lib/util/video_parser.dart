/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import '../models/video.dart';

/// Utilities for parsing video.txt files.
///
/// Supports both single-language and multilingual formats:
///
/// Single language:
/// ```
/// # VIDEO: Title Here
/// ```
///
/// Multilingual:
/// ```
/// # VIDEO_EN: English Title
/// # VIDEO_PT: Titulo em Portugues
/// ```
class VideoParser {
  VideoParser._();

  /// Parse video.txt content to Video model
  static Video parseVideoContent({
    required String content,
    required String videoId,
    required String folderPath,
  }) {
    final lines = content.split('\n');

    // Parse titles
    final titles = parseTitles(lines);

    // Parse metadata fields
    final metadata = parseMetadata(lines);

    // Parse descriptions
    final descriptions = parseDescriptions(content);

    // Parse NOSTR footer
    final nostrData = parseNostrFooter(lines);

    // Build Video object
    return Video(
      id: videoId,
      author: metadata['AUTHOR'] ?? '',
      created: metadata['CREATED'] ?? '',
      edited: metadata['EDITED'],
      titles: titles,
      descriptions: descriptions,
      duration: int.tryParse(metadata['DURATION'] ?? '0') ?? 0,
      resolution: metadata['RESOLUTION'] ?? '',
      fileSize: int.tryParse(metadata['FILE_SIZE'] ?? '0') ?? 0,
      mimeType: metadata['MIME_TYPE'] ?? 'video/mp4',
      category: VideoCategory.fromString(metadata['CATEGORY'] ?? 'other'),
      visibility: VideoVisibility.fromString(metadata['VISIBILITY'] ?? 'public'),
      tags: _parseCommaSeparated(metadata['TAGS']),
      latitude: _parseLatitude(metadata['COORDINATES']),
      longitude: _parseLongitude(metadata['COORDINATES']),
      websites: _parseCommaSeparated(metadata['WEBSITES']),
      social: _parseCommaSeparated(metadata['SOCIAL']),
      contact: metadata['CONTACT'],
      allowedGroups: _parseCommaSeparated(metadata['ALLOWED_GROUPS']),
      allowedUsers: _parseCommaSeparated(metadata['ALLOWED_USERS']),
      npub: nostrData['npub'],
      signature: nostrData['signature'],
      folderPath: folderPath,
    );
  }

  /// Parse titles from header lines
  /// Returns map of {langCode: title}
  static Map<String, String> parseTitles(List<String> lines) {
    final titles = <String, String>{};

    for (final line in lines) {
      final trimmed = line.trim();

      // Single language format: # VIDEO: Title
      if (trimmed.startsWith('# VIDEO:') && !trimmed.startsWith('# VIDEO_')) {
        final title = trimmed.substring(8).trim();
        if (title.isNotEmpty) {
          titles['EN'] = title;
        }
        break; // Single language, no more titles
      }

      // Multilingual format: # VIDEO_XX: Title
      if (trimmed.startsWith('# VIDEO_')) {
        // Extract language code (2 characters after VIDEO_)
        if (trimmed.length >= 11 && trimmed[10] == ':') {
          final langCode = trimmed.substring(8, 10).toUpperCase();
          final title = trimmed.substring(11).trim();
          if (title.isNotEmpty) {
            titles[langCode] = title;
          }
        }
      }

      // Stop at first non-title, non-empty line (but skip blank lines)
      if (!trimmed.startsWith('#') && trimmed.isNotEmpty) {
        break;
      }
    }

    return titles;
  }

  /// Parse metadata key-value pairs from content
  /// Returns map of {KEY: value}
  static Map<String, String> parseMetadata(List<String> lines) {
    final metadata = <String, String>{};

    for (final line in lines) {
      final trimmed = line.trim();

      // Skip title lines, comments, empty lines, language blocks, and NOSTR footer
      if (trimmed.startsWith('#') ||
          trimmed.isEmpty ||
          trimmed.startsWith('[') ||
          trimmed.startsWith('-->')) {
        continue;
      }

      // Look for KEY: value format
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        final key = trimmed.substring(0, colonIndex).trim().toUpperCase();
        final value = trimmed.substring(colonIndex + 1).trim();

        // Only store if key looks like a metadata field (all caps, alphanumeric + underscore)
        if (_isMetadataKey(key) && value.isNotEmpty) {
          metadata[key] = value;
        }
      }
    }

    return metadata;
  }

  /// Parse multilingual descriptions from content
  /// Returns map of {langCode: description}
  static Map<String, String> parseDescriptions(String content) {
    final descriptions = <String, String>{};
    final lines = content.split('\n');

    // Find where metadata ends and content begins
    int contentStart = 0;
    bool foundBlankAfterMeta = false;
    int blankLineCount = 0;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();

      // Skip title lines
      if (trimmed.startsWith('#')) continue;

      // Count blank lines after metadata
      if (trimmed.isEmpty) {
        blankLineCount++;
        if (blankLineCount >= 2) {
          foundBlankAfterMeta = true;
        }
        continue;
      }

      // If this is a metadata line, reset blank count
      if (_looksLikeMetadata(trimmed)) {
        blankLineCount = 0;
        continue;
      }

      // Found content start
      if (foundBlankAfterMeta || !_looksLikeMetadata(trimmed)) {
        contentStart = i;
        break;
      }
    }

    // Extract content section
    final contentLines = lines.sublist(contentStart);
    final contentText = contentLines.join('\n');

    // Check if multilingual format (has [XX] blocks)
    final langBlockPattern = RegExp(r'\[([A-Z]{2})\]');
    if (langBlockPattern.hasMatch(contentText)) {
      // Parse multilingual blocks
      String? currentLang;
      final currentContent = <String>[];

      for (final line in contentLines) {
        final trimmed = line.trim();

        // Skip NOSTR footer
        if (trimmed.startsWith('-->')) break;

        // Check for language block start
        final match = langBlockPattern.firstMatch(trimmed);
        if (match != null && trimmed == '[${match.group(1)}]') {
          // Save previous language content
          if (currentLang != null && currentContent.isNotEmpty) {
            descriptions[currentLang] = _cleanDescription(currentContent.join('\n'));
          }

          // Start new language block
          currentLang = match.group(1);
          currentContent.clear();
          continue;
        }

        // Add to current language content
        if (currentLang != null) {
          currentContent.add(line);
        }
      }

      // Save last language content
      if (currentLang != null && currentContent.isNotEmpty) {
        descriptions[currentLang] = _cleanDescription(currentContent.join('\n'));
      }
    } else {
      // Single language format - everything after metadata is description
      final descLines = <String>[];

      for (final line in contentLines) {
        final trimmed = line.trim();

        // Stop at NOSTR footer
        if (trimmed.startsWith('-->')) break;

        descLines.add(line);
      }

      if (descLines.isNotEmpty) {
        descriptions['EN'] = _cleanDescription(descLines.join('\n'));
      }
    }

    return descriptions;
  }

  /// Parse NOSTR footer (npub and signature)
  static Map<String, String?> parseNostrFooter(List<String> lines) {
    String? npub;
    String? signature;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('--> npub:')) {
        npub = trimmed.substring(9).trim();
      } else if (trimmed.startsWith('--> signature:')) {
        signature = trimmed.substring(14).trim();
      }
    }

    return {'npub': npub, 'signature': signature};
  }

  /// Parse folder.txt metadata
  static Map<String, String>? parseFolderMetadata(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) return null;

    final metadata = <String, String>{};

    // Check for folder header
    final firstLine = lines[0].trim();
    if (firstLine.startsWith('# FOLDER:')) {
      metadata['name'] = firstLine.substring(9).trim();
    } else {
      return null;
    }

    // Parse other metadata
    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('CREATED:')) {
        metadata['created'] = trimmed.substring(8).trim();
      } else if (trimmed.startsWith('AUTHOR:')) {
        metadata['author'] = trimmed.substring(7).trim();
      } else if (!trimmed.startsWith('#') && !trimmed.startsWith('-->')) {
        // Description (first non-metadata line)
        if (!metadata.containsKey('description')) {
          metadata['description'] = trimmed;
        }
      }
    }

    return metadata;
  }

  /// Validate video data and return list of errors
  static List<String> validateVideo(Map<String, dynamic> data) {
    final errors = <String>[];

    // Required fields
    if (data['titles'] == null || (data['titles'] as Map).isEmpty) {
      errors.add('Title is required');
    }
    if (data['author'] == null || (data['author'] as String).isEmpty) {
      errors.add('Author is required');
    }
    if (data['created'] == null || (data['created'] as String).isEmpty) {
      errors.add('Created timestamp is required');
    }
    if (data['duration'] == null || data['duration'] == 0) {
      errors.add('Duration is required');
    }
    if (data['resolution'] == null || (data['resolution'] as String).isEmpty) {
      errors.add('Resolution is required');
    }
    if (data['fileSize'] == null || data['fileSize'] == 0) {
      errors.add('File size is required');
    }
    if (data['mimeType'] == null || (data['mimeType'] as String).isEmpty) {
      errors.add('MIME type is required');
    }

    // Validate resolution format
    final resolution = data['resolution'] as String?;
    if (resolution != null && resolution.isNotEmpty) {
      if (!RegExp(r'^\d+x\d+$').hasMatch(resolution)) {
        errors.add('Resolution must be in format WxH (e.g., 1920x1080)');
      }
    }

    // Validate timestamp format
    final created = data['created'] as String?;
    if (created != null && created.isNotEmpty) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}_\d{2}$').hasMatch(created)) {
        errors.add('Created timestamp must be in format YYYY-MM-DD HH:MM_ss');
      }
    }

    // Validate MIME type
    final mimeType = data['mimeType'] as String?;
    if (mimeType != null && mimeType.isNotEmpty) {
      final validTypes = [
        'video/mp4',
        'video/webm',
        'video/quicktime',
        'video/x-msvideo',
        'video/x-matroska',
      ];
      if (!validTypes.contains(mimeType)) {
        errors.add('Invalid MIME type. Supported: ${validTypes.join(', ')}');
      }
    }

    // Validate coordinates if present
    final lat = data['latitude'] as double?;
    final lon = data['longitude'] as double?;
    if (lat != null && (lat < -90 || lat > 90)) {
      errors.add('Latitude must be between -90 and 90');
    }
    if (lon != null && (lon < -180 || lon > 180)) {
      errors.add('Longitude must be between -180 and 180');
    }

    // Validate visibility with allowed groups/users
    final visibility = data['visibility'] as String?;
    if (visibility == 'restricted') {
      final groups = data['allowedGroups'] as List?;
      final users = data['allowedUsers'] as List?;
      if ((groups == null || groups.isEmpty) && (users == null || users.isEmpty)) {
        errors.add('Restricted videos must have allowed groups or users');
      }
    }

    return errors;
  }

  // Helper methods

  static bool _isMetadataKey(String key) {
    return RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key);
  }

  static bool _looksLikeMetadata(String line) {
    final colonIndex = line.indexOf(':');
    if (colonIndex <= 0) return false;
    final key = line.substring(0, colonIndex).trim().toUpperCase();
    return _isMetadataKey(key);
  }

  static List<String> _parseCommaSeparated(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static double? _parseLatitude(String? coordinates) {
    if (coordinates == null || coordinates.isEmpty) return null;
    final parts = coordinates.split(',');
    if (parts.length != 2) return null;
    return double.tryParse(parts[0].trim());
  }

  static double? _parseLongitude(String? coordinates) {
    if (coordinates == null || coordinates.isEmpty) return null;
    final parts = coordinates.split(',');
    if (parts.length != 2) return null;
    return double.tryParse(parts[1].trim());
  }

  static String _cleanDescription(String description) {
    // Remove leading/trailing whitespace and collapse multiple blank lines
    final lines = description.split('\n');

    // Remove leading empty lines
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }

    // Remove trailing empty lines
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }

    return lines.join('\n').trim();
  }
}
