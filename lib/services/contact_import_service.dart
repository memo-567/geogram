/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contact.dart' as geogram;
import '../util/nostr_key_generator.dart';
import 'contact_service.dart';
import 'log_service.dart';

/// Model for device contact during import
class DeviceContactInfo {
  final String id;
  final String displayName;
  final List<String> emails;
  final List<String> phones;
  final List<String> addresses;
  final List<String> websites;
  final String? note;
  final Uint8List? photo;
  bool selected;
  bool isDuplicate;

  DeviceContactInfo({
    required this.id,
    required this.displayName,
    this.emails = const [],
    this.phones = const [],
    this.addresses = const [],
    this.websites = const [],
    this.note,
    this.photo,
    this.selected = true,
    this.isDuplicate = false,
  });
}

/// Result of import operation
class ImportResult {
  final int importedCount;
  final int skippedDuplicates;
  final int failedCount;
  final List<String> errors;

  ImportResult({
    this.importedCount = 0,
    this.skippedDuplicates = 0,
    this.failedCount = 0,
    this.errors = const [],
  });
}

/// Service for importing contacts from device
class ContactImportService {
  static final ContactImportService _instance = ContactImportService._internal();
  factory ContactImportService() => _instance;
  ContactImportService._internal();

  /// Check if import is available on this platform
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Check if contacts permission is granted
  Future<bool> hasContactsPermission() async {
    if (!isSupported) return false;
    final status = await Permission.contacts.status;
    return status.isGranted;
  }

  /// Request contacts permission (only called when user initiates import)
  Future<bool> requestContactsPermission() async {
    if (!isSupported) return false;

    LogService().log('ContactImport: Requesting contacts permission...');
    final status = await Permission.contacts.request();
    LogService().log('ContactImport: Permission status: ${status.name}');

    return status.isGranted;
  }

  /// Check if permission is permanently denied
  Future<bool> isPermissionPermanentlyDenied() async {
    if (!isSupported) return false;
    final status = await Permission.contacts.status;
    return status.isPermanentlyDenied;
  }

  /// Fetch all contacts from device
  Future<List<DeviceContactInfo>> fetchDeviceContacts() async {
    if (!isSupported) return [];

    LogService().log('ContactImport: Fetching device contacts...');

    try {
      // Request contacts with photo and all properties
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
        withThumbnail: false, // We use full photo
      );

      LogService().log('ContactImport: Found ${contacts.length} contacts');

      return contacts.map((contact) {
        return DeviceContactInfo(
          id: contact.id,
          displayName: contact.displayName.isNotEmpty
              ? contact.displayName
              : _buildDisplayName(contact),
          emails: contact.emails.map((e) => e.address).toList(),
          phones: contact.phones.map((p) => p.number).toList(),
          addresses: contact.addresses.map((a) => _formatAddress(a)).toList(),
          websites: contact.websites.map((w) => w.url).toList(),
          note: contact.notes.isNotEmpty ? contact.notes.first.note : null,
          photo: contact.photo,
        );
      }).where((c) => c.displayName.isNotEmpty).toList();
    } catch (e) {
      LogService().log('ContactImport: Error fetching contacts: $e');
      return [];
    }
  }

  /// Build display name from name parts
  String _buildDisplayName(Contact contact) {
    final parts = <String>[];
    if (contact.name.first.isNotEmpty) parts.add(contact.name.first);
    if (contact.name.last.isNotEmpty) parts.add(contact.name.last);
    if (parts.isEmpty && contact.emails.isNotEmpty) {
      return contact.emails.first.address.split('@').first;
    }
    if (parts.isEmpty && contact.phones.isNotEmpty) {
      return contact.phones.first.number;
    }
    return parts.join(' ');
  }

  /// Format address to single line
  String _formatAddress(Address address) {
    final parts = <String>[];
    if (address.street.isNotEmpty) parts.add(address.street);
    if (address.city.isNotEmpty) parts.add(address.city);
    if (address.state.isNotEmpty) parts.add(address.state);
    if (address.postalCode.isNotEmpty) parts.add(address.postalCode);
    if (address.country.isNotEmpty) parts.add(address.country);
    return parts.join(', ');
  }

  /// Mark duplicates in the list based on existing Geogram contacts
  Future<void> markDuplicates(
    List<DeviceContactInfo> deviceContacts,
    List<geogram.Contact> existingContacts,
  ) async {
    for (var device in deviceContacts) {
      device.isDuplicate = _isDuplicate(device, existingContacts);
      if (device.isDuplicate) {
        device.selected = false; // Don't pre-select duplicates
      }
    }
  }

  /// Check if device contact is a duplicate
  bool _isDuplicate(DeviceContactInfo device, List<geogram.Contact> existing) {
    for (var contact in existing) {
      // Check display name (case-insensitive)
      if (contact.displayName.toLowerCase() == device.displayName.toLowerCase()) {
        return true;
      }

      // Check emails
      for (var email in device.emails) {
        if (contact.emails.any((e) => e.toLowerCase() == email.toLowerCase())) {
          return true;
        }
      }

      // Check phones (normalize for comparison)
      for (var phone in device.phones) {
        final normalizedPhone = _normalizePhone(phone);
        if (contact.phones.any((p) => _normalizePhone(p) == normalizedPhone)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Normalize phone for comparison
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Import selected contacts
  Future<ImportResult> importContacts({
    required List<DeviceContactInfo> contacts,
    required String collectionPath,
    required String? groupPath,
    required Function(int imported, int total) onProgress,
  }) async {
    final contactService = ContactService();
    await contactService.initializeCollection(collectionPath);

    int imported = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    final selectedContacts = contacts.where((c) => c.selected && !c.isDuplicate).toList();
    final total = selectedContacts.length;

    for (var i = 0; i < selectedContacts.length; i++) {
      final device = selectedContacts[i];
      onProgress(i, total);

      try {
        // Generate temporary NOSTR identity
        final keys = NostrKeyGenerator.generateKeyPair();

        // Create timestamp
        final now = DateTime.now();
        final timestamp = '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}_'
            '${now.second.toString().padLeft(2, '0')}';

        // Save profile picture if available
        String? profilePicture;
        if (device.photo != null && device.photo!.isNotEmpty) {
          profilePicture = await contactService.saveProfilePictureFromBytes(
            keys.callsign,
            device.photo!,
            'jpg',
          );
        }

        // Create Geogram contact
        final contact = geogram.Contact(
          displayName: device.displayName,
          callsign: keys.callsign,
          npub: keys.npub,
          created: timestamp,
          firstSeen: timestamp,
          emails: device.emails,
          phones: device.phones,
          addresses: device.addresses,
          websites: device.websites,
          notes: device.note ?? '',
          profilePicture: profilePicture,
          isTemporaryIdentity: true,
          temporaryNsec: keys.nsec,
          tags: ['imported'],
          groupPath: groupPath,
        );

        // Save contact
        final error = await contactService.saveContact(contact, groupPath: groupPath);

        if (error != null) {
          failed++;
          errors.add('${device.displayName}: $error');
        } else {
          imported++;
        }
      } catch (e) {
        failed++;
        errors.add('${device.displayName}: $e');
        LogService().log('ContactImport: Error importing ${device.displayName}: $e');
      }
    }

    // Add skipped duplicates count
    skipped = contacts.where((c) => c.isDuplicate).length;

    LogService().log('ContactImport: Complete - imported=$imported, skipped=$skipped, failed=$failed');

    return ImportResult(
      importedCount: imported,
      skippedDuplicates: skipped,
      failedCount: failed,
      errors: errors,
    );
  }
}
