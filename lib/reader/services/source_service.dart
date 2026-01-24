/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import '../models/reader_models.dart';
import '../utils/reader_path_utils.dart';
import 'reader_storage_service.dart';
import '../../services/log_service.dart';

/// Service for loading and parsing source.js files
///
/// Note: This service parses the static configuration from source.js files.
/// For full JavaScript execution (custom crawlers), a JavaScript runtime
/// would need to be integrated (e.g., flutter_js or similar).
class SourceService {
  static final SourceService _instance = SourceService._internal();
  factory SourceService() => _instance;
  SourceService._internal();

  /// Load a source configuration from a source.js file
  Future<SourceConfig?> loadSourceConfig(String jsPath) async {
    try {
      final file = File(jsPath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return parseSourceJs(content);
    } catch (e) {
      LogService().log('SourceService: Error loading source.js: $e');
      return null;
    }
  }

  /// Parse source.js content to extract configuration
  ///
  /// This is a simple parser that extracts the module.exports object
  /// from a JavaScript source file. It handles basic cases but does
  /// not execute JavaScript code.
  SourceConfig? parseSourceJs(String content) {
    try {
      // Find module.exports = { ... } or export default { ... }
      String? jsonLike;

      // Try module.exports pattern
      final moduleExportsMatch =
          RegExp(r'module\.exports\s*=\s*\{', multiLine: true).firstMatch(content);
      if (moduleExportsMatch != null) {
        jsonLike = _extractObjectLiteral(content, moduleExportsMatch.end - 1);
      }

      // Try export default pattern
      if (jsonLike == null) {
        final exportDefaultMatch =
            RegExp(r'export\s+default\s*\{', multiLine: true).firstMatch(content);
        if (exportDefaultMatch != null) {
          jsonLike = _extractObjectLiteral(content, exportDefaultMatch.end - 1);
        }
      }

      if (jsonLike == null) {
        throw Exception('Could not find module.exports or export default');
      }

      // Convert JavaScript object literal to JSON-like format
      final json = _jsObjectToJson(jsonLike);

      // Parse as JSON
      final Map<String, dynamic> config = jsonDecode(json);
      return SourceConfig.fromJson(config);
    } catch (e) {
      LogService().log('SourceService: Error parsing source.js: $e');
      return null;
    }
  }

  /// Extract object literal from JavaScript code
  String _extractObjectLiteral(String content, int startIndex) {
    int braceCount = 0;
    int endIndex = startIndex;

    for (int i = startIndex; i < content.length; i++) {
      final char = content[i];
      if (char == '{') {
        braceCount++;
      } else if (char == '}') {
        braceCount--;
        if (braceCount == 0) {
          endIndex = i + 1;
          break;
        }
      }
    }

    return content.substring(startIndex, endIndex);
  }

  /// Convert JavaScript object literal to JSON format
  String _jsObjectToJson(String js) {
    var json = js;

    // Remove async functions (we can't parse them)
    json = json.replaceAll(
        RegExp(r'async\s+\w+\s*\([^)]*\)\s*\{[^}]*\}', multiLine: true, dotAll: true), '');

    // Remove function declarations
    json = json.replaceAll(
        RegExp(r'\w+\s*:\s*async\s+function[^}]+\}', multiLine: true, dotAll: true), '');
    json = json.replaceAll(
        RegExp(r'\w+\s*:\s*function[^}]+\}', multiLine: true, dotAll: true), '');

    // Remove arrow functions
    json = json.replaceAll(
        RegExp(r'\w+\s*:\s*\([^)]*\)\s*=>\s*\{[^}]*\}', multiLine: true, dotAll: true), '');
    json = json.replaceAll(
        RegExp(r'\w+\s*:\s*\w+\s*=>\s*\{[^}]*\}', multiLine: true, dotAll: true), '');

    // Handle trailing commas (valid in JS, invalid in JSON)
    json = json.replaceAll(RegExp(r',\s*\}'), '}');
    json = json.replaceAll(RegExp(r',\s*\]'), ']');

    // Add quotes around unquoted keys
    json = json.replaceAllMapped(
      RegExp(r'(\{|\,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
      (m) => '${m.group(1)}"${m.group(2)}":',
    );

    // Replace single quotes with double quotes (for string values)
    json = _replaceSingleQuotes(json);

    // Remove comments
    json = json.replaceAll(RegExp(r'//[^\n]*'), '');
    json = json.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    // Handle boolean values
    json = json.replaceAll(RegExp(r':\s*true\b'), ': true');
    json = json.replaceAll(RegExp(r':\s*false\b'), ': false');
    json = json.replaceAll(RegExp(r':\s*null\b'), ': null');

    // Clean up empty entries from removed functions
    json = json.replaceAll(RegExp(r',\s*,'), ',');
    json = json.replaceAll(RegExp(r'\{\s*,'), '{');
    json = json.replaceAll(RegExp(r',\s*\}'), '}');

    return json;
  }

  /// Replace single quotes with double quotes, avoiding nested quotes
  String _replaceSingleQuotes(String str) {
    final result = StringBuffer();
    bool inDoubleQuote = false;
    bool inSingleQuote = false;
    String? prevChar;

    for (int i = 0; i < str.length; i++) {
      final char = str[i];
      final isEscaped = prevChar == '\\';

      if (char == '"' && !isEscaped && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        result.write(char);
      } else if (char == "'" && !isEscaped && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        result.write('"'); // Replace with double quote
      } else {
        result.write(char);
      }

      prevChar = char;
    }

    return result.toString();
  }

  /// Create a Source from a SourceConfig
  Source createSourceFromConfig(
    SourceConfig config,
    String category,
    String sourceId,
    String path,
  ) {
    return Source(
      id: sourceId,
      name: config.name,
      type: config.type == 'manga' ? SourceType.manga : SourceType.rss,
      url: config.url,
      icon: config.icon,
      feedType: _parseFeedType(config.feedType),
      settings: config.settings != null
          ? SourceSettings.fromJson(config.settings!)
          : SourceSettings(),
      isLocal: config.local ?? false,
      path: path,
    );
  }

  FeedType _parseFeedType(String? type) {
    switch (type?.toLowerCase()) {
      case 'rss':
        return FeedType.rss;
      case 'atom':
        return FeedType.atom;
      case 'custom':
        return FeedType.custom;
      default:
        return FeedType.auto;
    }
  }

  /// Discover all sources in a category
  Future<List<Source>> discoverSources(
    String basePath,
    String category,
  ) async {
    final sources = <Source>[];

    try {
      final categoryDir = Directory('$basePath/$category');
      if (!await categoryDir.exists()) return sources;

      await for (final entity in categoryDir.list()) {
        if (entity is Directory) {
          final sourceId = entity.path.split('/').last;
          final jsPath =
              ReaderPathUtils.sourceJsFile(basePath, category, sourceId);

          final config = await loadSourceConfig(jsPath);
          if (config != null) {
            final source = createSourceFromConfig(
              config,
              category,
              sourceId,
              entity.path,
            );
            sources.add(source);
          }
        }
      }
    } catch (e) {
      LogService().log('SourceService: Error discovering sources: $e');
    }

    return sources;
  }

  /// Create a new source with default source.js
  Future<bool> createSource({
    required String basePath,
    required String category,
    required String name,
    required String url,
    String? feedType,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final sourceId = ReaderPathUtils.slugify(name);
      final sourcePath = ReaderPathUtils.sourceDir(basePath, category, sourceId);
      final jsPath = ReaderPathUtils.sourceJsFile(basePath, category, sourceId);

      // Create directory
      await Directory(sourcePath).create(recursive: true);

      // Create source.js
      final js = _generateSourceJs(
        name: name,
        type: category,
        url: url,
        feedType: feedType,
        settings: settings,
      );

      await File(jsPath).writeAsString(js);

      // Create initial data.json
      final source = Source(
        id: sourceId,
        name: name,
        type: category == 'manga' ? SourceType.manga : SourceType.rss,
        url: url,
        path: sourcePath,
      );

      final storage = ReaderStorageService(basePath);
      await storage.writeSource(category, source);

      return true;
    } catch (e) {
      LogService().log('SourceService: Error creating source: $e');
      return false;
    }
  }

  /// Generate source.js content
  String _generateSourceJs({
    required String name,
    required String type,
    required String url,
    String? feedType,
    Map<String, dynamic>? settings,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('// $name source configuration');
    buffer.writeln('module.exports = {');
    buffer.writeln('  name: "$name",');
    buffer.writeln('  type: "$type",');
    buffer.writeln('  url: "$url",');

    if (feedType != null) {
      buffer.writeln('  feedType: "$feedType",');
    }

    if (settings != null && settings.isNotEmpty) {
      buffer.writeln('  settings: {');
      settings.forEach((key, value) {
        if (value is String) {
          buffer.writeln('    $key: "$value",');
        } else {
          buffer.writeln('    $key: $value,');
        }
      });
      buffer.writeln('  },');
    }

    buffer.writeln('};');

    return buffer.toString();
  }
}
