/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import '../models/contact.dart';

/// Fields that can be selected for QR code sharing
enum ContactQrField {
  displayName,    // Always included (required)
  callsign,       // Always included (required)
  npub,
  emails,
  phones,
  addresses,
  websites,
  locations,
  socialHandles,
  tags,
  radioCallsigns,
  notes,
}

/// Status of QR code size
enum QrSizeStatus {
  ok,       // < 1000 bytes - safe
  warning,  // 1000-1500 bytes - may be slow to scan
  tooLarge, // > 1500 bytes - may not scan reliably
}

/// Service for encoding/decoding contacts to/from QR code JSON format
class ContactQrService {
  /// Required fields that are always included
  static const requiredFields = {ContactQrField.displayName, ContactQrField.callsign};

  /// Maximum recommended size for reliable QR scanning
  static const int maxRecommendedSize = 1500;

  /// Warning threshold for size
  static const int warningThreshold = 1000;

  /// Encode contact with selected fields to JSON string
  String encodeContact(Contact contact, Set<ContactQrField> selectedFields) {
    final fields = {...selectedFields, ...requiredFields}; // Always include required fields

    final json = <String, dynamic>{
      'geogram_contact': '1.0',
      'displayName': contact.displayName,
      'callsign': contact.callsign,
    };

    if (fields.contains(ContactQrField.npub) && contact.npub != null) {
      json['npub'] = contact.npub;
    }

    if (fields.contains(ContactQrField.emails) && contact.emails.isNotEmpty) {
      json['emails'] = contact.emails;
    }

    if (fields.contains(ContactQrField.phones) && contact.phones.isNotEmpty) {
      json['phones'] = contact.phones;
    }

    if (fields.contains(ContactQrField.addresses) && contact.addresses.isNotEmpty) {
      json['addresses'] = contact.addresses;
    }

    if (fields.contains(ContactQrField.websites) && contact.websites.isNotEmpty) {
      json['websites'] = contact.websites;
    }

    if (fields.contains(ContactQrField.locations) && contact.locations.isNotEmpty) {
      json['locations'] = contact.locations.map((l) => l.toJson()).toList();
    }

    if (fields.contains(ContactQrField.socialHandles) && contact.socialHandles.isNotEmpty) {
      json['socialHandles'] = contact.socialHandles;
    }

    if (fields.contains(ContactQrField.tags) && contact.tags.isNotEmpty) {
      json['tags'] = contact.tags;
    }

    if (fields.contains(ContactQrField.radioCallsigns) && contact.radioCallsigns.isNotEmpty) {
      json['radioCallsigns'] = contact.radioCallsigns;
    }

    if (fields.contains(ContactQrField.notes) && contact.notes.isNotEmpty) {
      json['notes'] = contact.notes;
    }

    return jsonEncode(json);
  }

  /// Calculate byte size of encoded JSON
  int calculateSize(String jsonData) {
    return utf8.encode(jsonData).length;
  }

  /// Check if size is within QR limits
  QrSizeStatus checkSizeStatus(int bytes) {
    if (bytes > maxRecommendedSize) {
      return QrSizeStatus.tooLarge;
    } else if (bytes > warningThreshold) {
      return QrSizeStatus.warning;
    }
    return QrSizeStatus.ok;
  }

  /// Get available fields for a contact (only fields that have data)
  List<ContactQrFieldInfo> getAvailableFields(Contact contact) {
    final fields = <ContactQrFieldInfo>[];

    // Required fields
    fields.add(ContactQrFieldInfo(
      field: ContactQrField.displayName,
      isRequired: true,
      count: 1,
      estimatedSize: _estimateFieldSize('displayName', contact.displayName),
    ));
    fields.add(ContactQrFieldInfo(
      field: ContactQrField.callsign,
      isRequired: true,
      count: 1,
      estimatedSize: _estimateFieldSize('callsign', contact.callsign),
    ));

    // Optional fields (only show if they have data)
    if (contact.npub != null && contact.npub!.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.npub,
        isRequired: false,
        count: 1,
        estimatedSize: _estimateFieldSize('npub', contact.npub!),
      ));
    }

    if (contact.emails.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.emails,
        isRequired: false,
        count: contact.emails.length,
        estimatedSize: _estimateListSize('emails', contact.emails),
      ));
    }

    if (contact.phones.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.phones,
        isRequired: false,
        count: contact.phones.length,
        estimatedSize: _estimateListSize('phones', contact.phones),
      ));
    }

    if (contact.addresses.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.addresses,
        isRequired: false,
        count: contact.addresses.length,
        estimatedSize: _estimateListSize('addresses', contact.addresses),
      ));
    }

    if (contact.websites.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.websites,
        isRequired: false,
        count: contact.websites.length,
        estimatedSize: _estimateListSize('websites', contact.websites),
      ));
    }

    if (contact.locations.isNotEmpty) {
      final locationsJson = contact.locations.map((l) => l.toJson()).toList();
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.locations,
        isRequired: false,
        count: contact.locations.length,
        estimatedSize: _estimateJsonSize('locations', locationsJson),
      ));
    }

    if (contact.socialHandles.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.socialHandles,
        isRequired: false,
        count: contact.socialHandles.length,
        estimatedSize: _estimateJsonSize('socialHandles', contact.socialHandles),
      ));
    }

    if (contact.tags.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.tags,
        isRequired: false,
        count: contact.tags.length,
        estimatedSize: _estimateListSize('tags', contact.tags),
      ));
    }

    if (contact.radioCallsigns.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.radioCallsigns,
        isRequired: false,
        count: contact.radioCallsigns.length,
        estimatedSize: _estimateListSize('radioCallsigns', contact.radioCallsigns),
      ));
    }

    if (contact.notes.isNotEmpty) {
      fields.add(ContactQrFieldInfo(
        field: ContactQrField.notes,
        isRequired: false,
        count: 1,
        estimatedSize: _estimateFieldSize('notes', contact.notes),
      ));
    }

    return fields;
  }

  int _estimateFieldSize(String key, String value) {
    // Key + quotes + colon + value + quotes + comma
    return key.length + value.length + 6;
  }

  int _estimateListSize(String key, List<String> values) {
    // Key + brackets + values with quotes and commas
    int size = key.length + 4;
    for (final v in values) {
      size += v.length + 3; // quotes + comma
    }
    return size;
  }

  int _estimateJsonSize(String key, dynamic value) {
    final encoded = jsonEncode({key: value});
    return encoded.length;
  }

  /// Decode JSON string back to Contact
  /// Returns null if JSON is invalid or not a Geogram contact
  Contact? decodeContact(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;

      // Check for Geogram contact identifier
      if (!json.containsKey('geogram_contact')) {
        return null;
      }

      // Required fields
      final displayName = json['displayName'] as String?;
      final callsign = json['callsign'] as String?;

      if (displayName == null || callsign == null) {
        return null;
      }

      // Generate timestamps for new contact
      final now = DateTime.now();
      final timestamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}_'
          '${now.second.toString().padLeft(2, '0')}';

      return Contact(
        displayName: displayName,
        callsign: callsign,
        npub: json['npub'] as String?,
        created: timestamp,
        firstSeen: timestamp,
        emails: json['emails'] != null ? List<String>.from(json['emails'] as List) : const [],
        phones: json['phones'] != null ? List<String>.from(json['phones'] as List) : const [],
        addresses: json['addresses'] != null ? List<String>.from(json['addresses'] as List) : const [],
        websites: json['websites'] != null ? List<String>.from(json['websites'] as List) : const [],
        locations: json['locations'] != null
            ? (json['locations'] as List).map((l) => ContactLocation.fromJson(l as Map<String, dynamic>)).toList()
            : const [],
        socialHandles: json['socialHandles'] != null
            ? Map<String, String>.from(json['socialHandles'] as Map)
            : const {},
        tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : const [],
        radioCallsigns: json['radioCallsigns'] != null ? List<String>.from(json['radioCallsigns'] as List) : const [],
        notes: json['notes'] as String? ?? '',
      );
    } catch (e) {
      return null;
    }
  }

  /// Check if a JSON string is a valid Geogram contact
  bool isValidGeogramContact(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;
      return json.containsKey('geogram_contact') &&
          json.containsKey('displayName') &&
          json.containsKey('callsign');
    } catch (e) {
      return false;
    }
  }

  /// Decode JSON string to Contact with exchange metadata
  /// Returns null if JSON is invalid or not a Geogram contact
  QrContactResult? decodeContactWithMetadata(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;

      // Check for Geogram contact identifier
      if (!json.containsKey('geogram_contact')) {
        return null;
      }

      // Required fields
      final displayName = json['displayName'] as String?;
      final callsign = json['callsign'] as String?;

      if (displayName == null || callsign == null) {
        return null;
      }

      // Generate timestamps for new contact
      final now = DateTime.now();
      final timestamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}_'
          '${now.second.toString().padLeft(2, '0')}';

      final contact = Contact(
        displayName: displayName,
        callsign: callsign,
        npub: json['npub'] as String?,
        created: timestamp,
        firstSeen: timestamp,
        emails: json['emails'] != null ? List<String>.from(json['emails'] as List) : const [],
        phones: json['phones'] != null ? List<String>.from(json['phones'] as List) : const [],
        addresses: json['addresses'] != null ? List<String>.from(json['addresses'] as List) : const [],
        websites: json['websites'] != null ? List<String>.from(json['websites'] as List) : const [],
        locations: json['locations'] != null
            ? (json['locations'] as List).map((l) => ContactLocation.fromJson(l as Map<String, dynamic>)).toList()
            : const [],
        socialHandles: json['socialHandles'] != null
            ? Map<String, String>.from(json['socialHandles'] as Map)
            : const {},
        tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : const [],
        radioCallsigns: json['radioCallsigns'] != null ? List<String>.from(json['radioCallsigns'] as List) : const [],
        notes: json['notes'] as String? ?? '',
      );

      // Extract exchange metadata
      return QrContactResult(
        contact: contact,
        exchangeNote: json['exchange_note'] as String?,
        exchangeLat: json['exchange_lat'] != null ? (json['exchange_lat'] as num).toDouble() : null,
        exchangeLon: json['exchange_lon'] != null ? (json['exchange_lon'] as num).toDouble() : null,
        exchangeEventId: json['exchange_event'] as String?,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Information about a QR field for UI display
class ContactQrFieldInfo {
  final ContactQrField field;
  final bool isRequired;
  final int count;
  final int estimatedSize;

  ContactQrFieldInfo({
    required this.field,
    required this.isRequired,
    required this.count,
    required this.estimatedSize,
  });
}

/// Result of decoding a QR contact, including optional exchange metadata
class QrContactResult {
  final Contact contact;
  final String? exchangeNote;
  final double? exchangeLat;
  final double? exchangeLon;
  final String? exchangeEventId;

  QrContactResult({
    required this.contact,
    this.exchangeNote,
    this.exchangeLat,
    this.exchangeLon,
    this.exchangeEventId,
  });

  bool get hasLocation => exchangeLat != null && exchangeLon != null;
  bool get hasEvent => exchangeEventId != null && exchangeEventId!.isNotEmpty;
  bool get hasNote => exchangeNote != null && exchangeNote!.isNotEmpty;
  bool get hasExchangeMetadata => hasLocation || hasEvent || hasNote;
}
