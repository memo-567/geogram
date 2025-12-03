// CLI Location Service - Pure Dart implementation for IP-based geolocation
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
class CliLocationService {
  static final CliLocationService _instance = CliLocationService._internal();
  factory CliLocationService() => _instance;
  CliLocationService._internal();

  /// Detect location via IP address using ip-api.com (free, no API key required)
  Future<GeoIpResult?> detectLocationViaIP() async {
    try {
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/?fields=status,lat,lon,city,country'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return GeoIpResult(
            latitude: (data['lat'] as num).toDouble(),
            longitude: (data['lon'] as num).toDouble(),
            city: data['city'] as String?,
            country: data['country'] as String?,
          );
        } else {
          stderr.writeln('IP geolocation failed: ${data['message'] ?? 'unknown error'}');
        }
      } else {
        stderr.writeln('IP geolocation request failed with status: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      stderr.writeln('Failed to detect location via IP: $e');
      return null;
    }
  }
}
