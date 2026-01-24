/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Type of book file
enum BookFormat {
  epub,
  pdf,
  txt,
  md,
}

/// A book file
class Book {
  final String filename;
  final String path;
  final BookFormat format;
  final String title;
  final String? author;
  final String? description;
  final String? thumbnail;
  final int? totalPages;
  final DateTime? publishedAt;
  final DateTime modifiedAt;

  Book({
    required this.filename,
    required this.path,
    required this.format,
    required this.title,
    this.author,
    this.description,
    this.thumbnail,
    this.totalPages,
    this.publishedAt,
    DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime.now();

  factory Book.fromFile(String path, String filename) {
    final format = _parseFormat(filename);
    return Book(
      filename: filename,
      path: path,
      format: format,
      title: _extractTitle(filename),
    );
  }

  factory Book.fromJson(Map<String, dynamic> json, String path) {
    return Book(
      filename: json['filename'] as String,
      path: path,
      format: BookFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => BookFormat.txt,
      ),
      title: json['title'] as String,
      author: json['author'] as String?,
      description: json['description'] as String?,
      thumbnail: json['thumbnail'] as String?,
      totalPages: json['total_pages'] as int?,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      modifiedAt: json['modified_at'] != null
          ? DateTime.parse(json['modified_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'format': format.name,
      'title': title,
      'author': author,
      'description': description,
      'thumbnail': thumbnail,
      'total_pages': totalPages,
      'published_at': publishedAt?.toIso8601String(),
      'modified_at': modifiedAt.toIso8601String(),
    };
  }

  static BookFormat _parseFormat(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'epub':
        return BookFormat.epub;
      case 'pdf':
        return BookFormat.pdf;
      case 'txt':
        return BookFormat.txt;
      case 'md':
        return BookFormat.md;
      default:
        return BookFormat.txt;
    }
  }

  static String _extractTitle(String filename) {
    // Remove extension
    final noExt = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
    // Replace underscores and hyphens with spaces
    final cleaned = noExt.replaceAll(RegExp(r'[_-]'), ' ');
    // Capitalize first letter of each word
    return cleaned
        .split(' ')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String get fullPath => '$path/$filename';

  String get extension => filename.split('.').last.toLowerCase();

  Book copyWith({
    String? filename,
    String? path,
    BookFormat? format,
    String? title,
    String? author,
    String? description,
    String? thumbnail,
    int? totalPages,
    DateTime? publishedAt,
    DateTime? modifiedAt,
  }) {
    return Book(
      filename: filename ?? this.filename,
      path: path ?? this.path,
      format: format ?? this.format,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      thumbnail: thumbnail ?? this.thumbnail,
      totalPages: totalPages ?? this.totalPages,
      publishedAt: publishedAt ?? this.publishedAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }
}

/// Folder metadata for book organization
class BookFolder {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final String? sortOrder;
  final DateTime createdAt;
  final DateTime modifiedAt;

  BookFolder({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.color,
    this.sortOrder,
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  factory BookFolder.fromJson(Map<String, dynamic> json, String id) {
    return BookFolder(
      id: id,
      name: json['name'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: json['sort_order'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      modifiedAt: json['modified_at'] != null
          ? DateTime.parse(json['modified_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'modified_at': modifiedAt.toIso8601String(),
    };
  }
}
