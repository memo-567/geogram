/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/reader_models.dart';
import '../utils/reader_path_utils.dart';
import '../../services/log_service.dart';

/// Service for parsing RSS and Atom feeds
class RssService {
  static final RssService _instance = RssService._internal();
  factory RssService() => _instance;
  RssService._internal();

  /// Fetch and parse a feed
  Future<List<RssFeedItem>> fetchFeed(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch feed: ${response.statusCode}');
      }

      final content = response.body;
      return parseFeed(content);
    } catch (e) {
      LogService().log('RssService: Error fetching feed: $e');
      rethrow;
    }
  }

  /// Parse feed content (auto-detect RSS vs Atom)
  List<RssFeedItem> parseFeed(String content) {
    try {
      final document = XmlDocument.parse(content);

      // Detect feed type
      final rssElements = document.findAllElements('rss');
      if (rssElements.isNotEmpty) {
        return _parseRss(document);
      }

      final atomElements = document.findAllElements('feed');
      if (atomElements.isNotEmpty) {
        return _parseAtom(document);
      }

      throw Exception('Unknown feed format');
    } catch (e) {
      LogService().log('RssService: Error parsing feed: $e');
      rethrow;
    }
  }

  /// Parse RSS 2.0 feed
  List<RssFeedItem> _parseRss(XmlDocument document) {
    final items = <RssFeedItem>[];

    for (final item in document.findAllElements('item')) {
      final title = _getElementText(item, 'title') ?? 'Untitled';
      final link = _getElementText(item, 'link') ?? '';
      final guid = _getElementText(item, 'guid');
      final description = _getElementText(item, 'description');
      final author = _getElementText(item, 'author') ??
          _getElementText(item, 'dc:creator');
      final pubDate = _getElementText(item, 'pubDate');
      final content = _getElementText(item, 'content:encoded');
      final categories = item
          .findElements('category')
          .map((e) => e.innerText.trim())
          .toList();

      // Extract images from description/content
      final imageUrls = _extractImageUrls(content ?? description ?? '');

      items.add(RssFeedItem(
        id: guid ?? link,
        title: title,
        url: link,
        author: author,
        publishedAt: _parseDate(pubDate),
        summary: _stripHtml(description ?? ''),
        content: content ?? description,
        categories: categories,
        imageUrls: imageUrls,
      ));
    }

    return items;
  }

  /// Parse Atom feed
  List<RssFeedItem> _parseAtom(XmlDocument document) {
    final items = <RssFeedItem>[];

    for (final entry in document.findAllElements('entry')) {
      final title = _getElementText(entry, 'title') ?? 'Untitled';

      // Get link - prefer 'alternate' type
      String? link;
      for (final linkElement in entry.findElements('link')) {
        final rel = linkElement.getAttribute('rel');
        final href = linkElement.getAttribute('href');
        if (href != null) {
          if (rel == 'alternate' || rel == null) {
            link = href;
            break;
          }
          link ??= href;
        }
      }

      final id = _getElementText(entry, 'id');
      final summary = _getElementText(entry, 'summary');
      final content = _getElementText(entry, 'content');
      final published = _getElementText(entry, 'published') ??
          _getElementText(entry, 'updated');

      // Get author
      String? author;
      final authorElement = entry.findElements('author').firstOrNull;
      if (authorElement != null) {
        author = _getElementText(authorElement, 'name');
      }

      // Get categories
      final categories = entry.findElements('category').map((e) {
        return e.getAttribute('term') ?? e.getAttribute('label') ?? '';
      }).where((s) => s.isNotEmpty).toList();

      // Extract images
      final imageUrls = _extractImageUrls(content ?? summary ?? '');

      items.add(RssFeedItem(
        id: id ?? link,
        title: title,
        url: link ?? '',
        author: author,
        publishedAt: _parseDate(published),
        summary: _stripHtml(summary ?? ''),
        content: content ?? summary,
        categories: categories,
        imageUrls: imageUrls,
      ));
    }

    return items;
  }

  /// Get text content of an element
  String? _getElementText(XmlElement parent, String name) {
    final element = parent.findElements(name).firstOrNull;
    if (element == null) return null;
    final text = element.innerText.trim();
    return text.isEmpty ? null : text;
  }

  /// Parse various date formats
  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;

    // Try RFC 822 (RSS)
    try {
      return _parseRfc822Date(dateStr);
    } catch (_) {}

    // Try ISO 8601 (Atom)
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}

    return null;
  }

  /// Parse RFC 822 date format (used by RSS)
  DateTime _parseRfc822Date(String dateStr) {
    // Example: "Sat, 21 Sep 2024 09:00:00 +0000"
    final months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };

    final regex = RegExp(
        r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})');
    final match = regex.firstMatch(dateStr);
    if (match == null) throw FormatException('Invalid RFC 822 date');

    final day = int.parse(match.group(1)!);
    final month = months[match.group(2)!] ?? 1;
    final year = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    return DateTime.utc(year, month, day, hour, minute, second);
  }

  /// Extract image URLs from HTML content
  List<String> _extractImageUrls(String html) {
    final urls = <String>[];
    final imgRegex = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false);

    for (final match in imgRegex.allMatches(html)) {
      final url = match.group(1);
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }

    return urls;
  }

  /// Strip HTML tags from content
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Convert HTML content to markdown
  String htmlToMarkdown(String html) {
    var md = html;

    // Headers
    md = md.replaceAllMapped(
      RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true),
      (m) => '# ${_stripHtml(m.group(1) ?? '')}\n\n',
    );
    md = md.replaceAllMapped(
      RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false, dotAll: true),
      (m) => '## ${_stripHtml(m.group(1) ?? '')}\n\n',
    );
    md = md.replaceAllMapped(
      RegExp(r'<h3[^>]*>(.*?)</h3>', caseSensitive: false, dotAll: true),
      (m) => '### ${_stripHtml(m.group(1) ?? '')}\n\n',
    );

    // Paragraphs
    md = md.replaceAllMapped(
      RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
      (m) => '${m.group(1)}\n\n',
    );

    // Links
    md = md.replaceAllMapped(
      RegExp(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
          caseSensitive: false, dotAll: true),
      (m) => '[${_stripHtml(m.group(2) ?? '')}](${m.group(1)})',
    );

    // Images
    md = md.replaceAllMapped(
      RegExp(r'<img[^>]+src="([^"]+)"[^>]*alt="([^"]*)"[^>]*>',
          caseSensitive: false),
      (m) => '![${m.group(2)}](${m.group(1)})',
    );
    md = md.replaceAllMapped(
      RegExp(r'<img[^>]+src="([^"]+)"[^>]*>', caseSensitive: false),
      (m) => '![](${m.group(1)})',
    );

    // Bold and italic
    md = md.replaceAllMapped(
      RegExp(r'<(strong|b)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
      (m) => '**${m.group(2)}**',
    );
    md = md.replaceAllMapped(
      RegExp(r'<(em|i)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
      (m) => '*${m.group(2)}*',
    );

    // Lists
    md = md.replaceAllMapped(
      RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true),
      (m) => '- ${_stripHtml(m.group(1) ?? '')}\n',
    );

    // Code
    md = md.replaceAllMapped(
      RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false, dotAll: true),
      (m) => '`${m.group(1)}`',
    );
    md = md.replaceAllMapped(
      RegExp(r'<pre[^>]*>(.*?)</pre>', caseSensitive: false, dotAll: true),
      (m) => '```\n${_stripHtml(m.group(1) ?? '')}\n```\n\n',
    );

    // Blockquotes
    md = md.replaceAllMapped(
      RegExp(r'<blockquote[^>]*>(.*?)</blockquote>',
          caseSensitive: false, dotAll: true),
      (m) => '> ${_stripHtml(m.group(1) ?? '')}\n\n',
    );

    // Line breaks
    md = md.replaceAll(RegExp(r'<br\s*/?>'), '\n');

    // Remove remaining HTML tags
    md = md.replaceAll(RegExp(r'<[^>]*>'), '');

    // Decode HTML entities
    md = md
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    // Clean up multiple newlines
    md = md.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return md.trim();
  }

  /// Convert feed item to RssPost
  RssPost feedItemToPost(RssFeedItem item, {String? sourceId}) {
    final publishedAt = item.publishedAt ?? DateTime.now();
    final slug = ReaderPathUtils.postSlug(publishedAt, item.title);

    return RssPost(
      id: 'post_$slug',
      title: item.title,
      author: item.author,
      publishedAt: publishedAt,
      fetchedAt: DateTime.now(),
      url: item.url,
      guid: item.id ?? item.url,
      summary: item.summary,
      wordCount: _countWords(item.content ?? item.summary ?? ''),
      readTimeMinutes: _estimateReadTime(item.content ?? item.summary ?? ''),
      categories: item.categories,
      images: [],
      isRead: false,
      isStarred: false,
    );
  }

  int _countWords(String text) {
    final stripped = _stripHtml(text);
    if (stripped.isEmpty) return 0;
    return stripped.split(RegExp(r'\s+')).length;
  }

  int _estimateReadTime(String text) {
    final wordCount = _countWords(text);
    // Average reading speed: 200-250 words per minute
    return (wordCount / 200).ceil();
  }
}
