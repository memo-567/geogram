/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Station info model for API responses.
 */

/// Station info for API responses.
///
/// Contains station metadata that is included in API responses
/// to identify which station served the request.
class StationInfo {
  final String? name;
  final String? callsign;
  final String? npub;

  StationInfo({this.name, this.callsign, this.npub});

  Map<String, dynamic> toJson() => {
        'name': name ?? 'Geogram Station',
        'callsign': callsign,
        'npub': npub,
      };
}
