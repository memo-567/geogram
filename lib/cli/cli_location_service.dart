// CLI Location Service - Pure Dart implementation for IP-based geolocation
// Uses connected station's GeoIP service for privacy-preserving location detection
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Result of IP-based geolocation
class GeoIpResult {
  final double latitude;
  final double longitude;
  final String? city;
  final String? country;

  GeoIpResult({
    required this.latitude,
    required this.longitude,
    this.city,
    this.country,
  });

  String get locationName {
    if (city != null && country != null) {
      return '$city, $country';
    } else if (city != null) {
      return city!;
    } else if (country != null) {
      return country!;
    }
    return 'Unknown';
  }
}

/// CLI Location Service - provides IP-based geolocation for CLI mode
/// Uses the connected station's /api/geoip endpoint for privacy-preserving geolocation
class CliLocationService {
  static final CliLocationService _instance = CliLocationService._internal();
  factory CliLocationService() => _instance;
  CliLocationService._internal();

  /// Connected station URL (should be set when connecting to a station)
  String? _stationUrl;

  /// Set the station URL for GeoIP lookups
  void setStationUrl(String? url) {
    _stationUrl = url;
  }

  /// Get the station URL
  String? get stationUrl => _stationUrl;

  /// Detect location via IP address using the connected station's GeoIP service
  /// This provides privacy-preserving IP geolocation without external API calls
  ///
  /// [stationUrl] - Optional station URL override (if not set via setStationUrl)
  Future<GeoIpResult?> detectLocationViaIP({String? stationUrl}) async {
    final url = stationUrl ?? _stationUrl;
    if (url == null) {
      stderr.writeln('CliLocationService: No station URL configured, cannot detect IP location');
      return null;
    }

    try {
      // Convert WebSocket URL to HTTP URL if needed
      final httpUrl = url
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');

      final response = await http.get(
        Uri.parse('$httpUrl/api/geoip'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();

        if (lat != null && lon != null) {
          return GeoIpResult(
            latitude: lat,
            longitude: lon,
            city: data['city'] as String?,
            country: data['country'] as String?,
          );
        } else {
          stderr.writeln('CliLocationService: Station GeoIP returned no location data');
        }
      } else if (response.statusCode == 503) {
        stderr.writeln('CliLocationService: Station GeoIP service not initialized');
      } else {
        stderr.writeln('CliLocationService: Station GeoIP failed with status: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      stderr.writeln('CliLocationService: Failed to detect location via station GeoIP: $e');
      return null;
    }
  }
}
