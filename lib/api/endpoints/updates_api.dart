/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Updates API endpoints.
 */

import '../api.dart';

/// Release info
class ReleaseInfo {
  final String version;
  final String? name;
  final String? description;
  final String? releaseNotes;
  final DateTime? publishedAt;
  final String? downloadUrl;
  final int? downloadSize;
  final String? checksum;
  final bool isPrerelease;

  const ReleaseInfo({
    required this.version,
    this.name,
    this.description,
    this.releaseNotes,
    this.publishedAt,
    this.downloadUrl,
    this.downloadSize,
    this.checksum,
    this.isPrerelease = false,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseInfo(
      version: json['version'] as String? ?? json['tag_name'] as String? ?? '',
      name: json['name'] as String?,
      description: json['description'] as String?,
      releaseNotes: json['releaseNotes'] as String? ?? json['body'] as String?,
      publishedAt: _parseDateTime(json['publishedAt'] ?? json['published_at']),
      downloadUrl: json['downloadUrl'] as String? ?? json['download_url'] as String?,
      downloadSize: json['downloadSize'] as int? ?? json['download_size'] as int?,
      checksum: json['checksum'] as String? ?? json['sha256'] as String?,
      isPrerelease: json['isPrerelease'] as bool? ?? json['prerelease'] as bool? ?? false,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Parse version into comparable parts
  List<int> get versionParts {
    return version
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
  }

  /// Compare versions: returns 1 if this is newer, -1 if older, 0 if same
  int compareVersion(String other) {
    final otherParts = other
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    final thisParts = versionParts;

    for (int i = 0; i < 3; i++) {
      final a = i < thisParts.length ? thisParts[i] : 0;
      final b = i < otherParts.length ? otherParts[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  /// Check if this version is newer than the given version
  bool isNewerThan(String other) => compareVersion(other) > 0;

  @override
  String toString() => 'ReleaseInfo($version)';
}

/// Updates API endpoints
class UpdatesApi {
  final GeogramApi _api;

  UpdatesApi(this._api);

  /// Get latest release info
  ///
  /// Returns information about the latest available version from the station.
  Future<ApiResponse<ReleaseInfo>> latest(
    String callsign, {
    String? platform,
    bool includePrerelease = false,
  }) {
    return _api.get<ReleaseInfo>(
      callsign,
      '/api/updates/latest',
      queryParams: {
        if (platform != null) 'platform': platform,
        if (includePrerelease) 'prerelease': 'true',
      },
      fromJson: (json) => ReleaseInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Check if an update is available
  ///
  /// Convenience method that compares current version with latest.
  Future<ApiResponse<bool>> checkForUpdate(
    String callsign,
    String currentVersion, {
    String? platform,
    bool includePrerelease = false,
  }) async {
    final response = await latest(
      callsign,
      platform: platform,
      includePrerelease: includePrerelease,
    );

    if (!response.success || response.data == null) {
      return ApiResponse<bool>(
        success: response.success,
        error: response.error,
        data: false,
      );
    }

    final isNewer = response.data!.isNewerThan(currentVersion);
    return ApiResponse.ok(isNewer);
  }
}
