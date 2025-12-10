/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Represents a device paired via Bluetooth Classic for BLE+ functionality
class BluetoothClassicDevice {
  /// Callsign of the paired device (stable identifier)
  final String callsign;

  /// Bluetooth Classic MAC address (used for RFCOMM connections)
  final String classicMac;

  /// BLE MAC address (may differ from classicMac, especially on Android)
  final String? bleMac;

  /// When the pairing was established
  final DateTime pairedAt;

  /// Last time a successful connection was made
  DateTime? lastConnected;

  /// Device capabilities (e.g., ['spp', 'rfcomm'])
  final List<String> capabilities;

  BluetoothClassicDevice({
    required this.callsign,
    required this.classicMac,
    this.bleMac,
    required this.pairedAt,
    this.lastConnected,
    this.capabilities = const ['spp'],
  });

  /// Create from JSON (for storage/retrieval)
  factory BluetoothClassicDevice.fromJson(Map<String, dynamic> json) {
    return BluetoothClassicDevice(
      callsign: json['callsign'] as String,
      classicMac: json['classicMac'] as String,
      bleMac: json['bleMac'] as String?,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['spp'],
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'callsign': callsign,
      'classicMac': classicMac,
      'bleMac': bleMac,
      'pairedAt': pairedAt.toIso8601String(),
      'lastConnected': lastConnected?.toIso8601String(),
      'capabilities': capabilities,
    };
  }

  /// Update last connected timestamp
  BluetoothClassicDevice copyWithLastConnected(DateTime time) {
    return BluetoothClassicDevice(
      callsign: callsign,
      classicMac: classicMac,
      bleMac: bleMac,
      pairedAt: pairedAt,
      lastConnected: time,
      capabilities: capabilities,
    );
  }

  @override
  String toString() {
    return 'BluetoothClassicDevice(callsign: $callsign, classicMac: $classicMac, '
        'bleMac: $bleMac, pairedAt: $pairedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BluetoothClassicDevice &&
        other.callsign == callsign &&
        other.classicMac == classicMac;
  }

  @override
  int get hashCode => callsign.hashCode ^ classicMac.hashCode;
}
