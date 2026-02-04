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
  final Map<String, String> socialHandles;
  final List<geogram.ContactDateReminder> dateReminders;
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
    this.socialHandles = const {},
    this.dateReminders = const [],
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
      // Request contacts with properties and thumbnails for faster imports
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withThumbnail: true,
        withPhoto: false,
        sorted: false,
      );

      LogService().log('ContactImport: Found ${contacts.length} contacts');

      return contacts
          .map(_buildDeviceContactInfo)
          .where((c) => c.displayName.isNotEmpty)
          .toList();
    } catch (e) {
      LogService().log('ContactImport: Error fetching contacts: $e');
      return [];
    }
  }

  /// Build display name from name parts
  String _buildDisplayName(Contact contact) {
    final parts = <String>[];
    if (contact.name.prefix.isNotEmpty) parts.add(contact.name.prefix);
    if (contact.name.first.isNotEmpty) parts.add(contact.name.first);
    if (contact.name.middle.isNotEmpty) parts.add(contact.name.middle);
    if (contact.name.last.isNotEmpty) parts.add(contact.name.last);
    if (contact.name.suffix.isNotEmpty) parts.add(contact.name.suffix);
    if (parts.isEmpty && contact.name.nickname.isNotEmpty) {
      return contact.name.nickname;
    }
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
    final formatted = address.address.trim();
    final base = formatted.isNotEmpty ? formatted : _formatAddressParts(address);
    if (base.isEmpty) return '';
    final label = _formatAddressLabel(address);
    final singleLine = base.replaceAll(RegExp(r'[\r\n]+'), ', ').trim();
    if (singleLine.isEmpty) return '';
    return label != null ? '$label: $singleLine' : singleLine;
  }

  String _formatAddressParts(Address address) {
    final parts = <String>[];
    if (address.street.isNotEmpty) parts.add(address.street);
    if (address.pobox.isNotEmpty) parts.add(address.pobox);
    if (address.neighborhood.isNotEmpty) parts.add(address.neighborhood);
    if (address.subLocality.isNotEmpty) parts.add(address.subLocality);
    if (address.city.isNotEmpty) parts.add(address.city);
    if (address.subAdminArea.isNotEmpty) parts.add(address.subAdminArea);
    if (address.state.isNotEmpty) parts.add(address.state);
    if (address.postalCode.isNotEmpty) parts.add(address.postalCode);
    if (address.country.isNotEmpty) parts.add(address.country);
    if (address.isoCountry.isNotEmpty) parts.add(address.isoCountry);
    return parts.join(', ');
  }

  String? _formatAddressLabel(Address address) {
    switch (address.label) {
      case AddressLabel.custom:
        final custom = address.customLabel.trim();
        return custom.isNotEmpty ? custom : null;
      case AddressLabel.other:
        return 'other';
      case AddressLabel.home:
      case AddressLabel.school:
      case AddressLabel.work:
        return address.label.name;
    }
  }

  DeviceContactInfo _buildDeviceContactInfo(Contact contact) {
    final displayName = (contact.displayName.isNotEmpty
            ? contact.displayName
            : _buildDisplayName(contact))
        .trim();

    return DeviceContactInfo(
      id: contact.id,
      displayName: displayName,
      emails: _cleanEmails(contact.emails.map((e) => e.address)),
      phones: _cleanPhones(contact.phones.map((p) => p.number)),
      addresses: _cleanAddresses(contact.addresses.map(_formatAddress)),
      websites: _cleanWebsites(contact.websites.map((w) => w.url)),
      socialHandles: _buildSocialHandles(contact.socialMedias),
      dateReminders: _buildDateReminders(contact.events),
      note: _combineNotes(contact.notes),
      photo: contact.photoOrThumbnail,
    );
  }

  Future<DeviceContactInfo> _hydrateDeviceContact(DeviceContactInfo device) async {
    if (!_needsHydration(device)) return device;

    try {
      final contact = await FlutterContacts.getContact(
        device.id,
        withProperties: true,
        withPhoto: true,
        withThumbnail: false,
        deduplicateProperties: true,
      );
      if (contact == null) return device;

      final hydrated = _buildDeviceContactInfo(contact);
      return _mergeDeviceContactInfo(device, hydrated);
    } catch (e) {
      LogService().log('ContactImport: Error hydrating ${device.displayName}: $e');
      return device;
    }
  }

  bool _needsHydration(DeviceContactInfo device) {
    final hasPhoto = device.photo != null && device.photo!.isNotEmpty;
    final hasAddresses = device.addresses.isNotEmpty;
    return !hasPhoto || !hasAddresses;
  }

  DeviceContactInfo _mergeDeviceContactInfo(
    DeviceContactInfo base,
    DeviceContactInfo hydrated,
  ) {
    return DeviceContactInfo(
      id: base.id,
      displayName: base.displayName,
      emails: _mergeLists(base.emails, hydrated.emails, (value) => value.toLowerCase()),
      phones: _mergeLists(base.phones, hydrated.phones, _normalizePhone),
      addresses: _mergeLists(base.addresses, hydrated.addresses, (value) => value.toLowerCase()),
      websites: _mergeLists(base.websites, hydrated.websites, (value) => value.toLowerCase()),
      socialHandles: {...hydrated.socialHandles, ...base.socialHandles},
      dateReminders: _mergeDateReminders(base.dateReminders, hydrated.dateReminders),
      note: _mergeNotes(base.note, hydrated.note),
      photo: (base.photo != null && base.photo!.isNotEmpty) ? base.photo : hydrated.photo,
      selected: base.selected,
      isDuplicate: base.isDuplicate,
    );
  }

  List<String> _mergeLists(
    List<String> primary,
    List<String> secondary,
    String Function(String value) normalize,
  ) {
    return _dedupeByNormalized(
      <String>[...primary, ...secondary],
      normalize,
    );
  }

  List<geogram.ContactDateReminder> _mergeDateReminders(
    List<geogram.ContactDateReminder> primary,
    List<geogram.ContactDateReminder> secondary,
  ) {
    if (primary.isEmpty && secondary.isEmpty) {
      return const <geogram.ContactDateReminder>[];
    }

    final seen = <String>{};
    final merged = <geogram.ContactDateReminder>[];

    void addReminder(geogram.ContactDateReminder reminder) {
      final key = reminder.toFileFormat();
      if (seen.add(key)) {
        merged.add(reminder);
      }
    }

    for (final reminder in primary) {
      addReminder(reminder);
    }
    for (final reminder in secondary) {
      addReminder(reminder);
    }

    return merged;
  }

  String? _mergeNotes(String? primary, String? secondary) {
    final notes = <String>{};
    final ordered = <String>[];

    void addNote(String? note) {
      final trimmed = note?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      if (notes.add(trimmed)) {
        ordered.add(trimmed);
      }
    }

    addNote(primary);
    addNote(secondary);

    if (ordered.isEmpty) return null;
    return ordered.join('\n\n');
  }

  List<String> _cleanEmails(Iterable<String> emails) {
    return _dedupeByNormalized(emails, (email) => email.toLowerCase());
  }

  List<String> _cleanPhones(Iterable<String> phones) {
    return _dedupeByNormalized(phones, _normalizePhone);
  }

  List<String> _cleanWebsites(Iterable<String> websites) {
    return _dedupeByNormalized(websites, (website) => website.toLowerCase());
  }

  List<String> _cleanAddresses(Iterable<String> addresses) {
    return _dedupeByNormalized(addresses, (address) => address.toLowerCase());
  }

  String? _combineNotes(List<Note> notes) {
    if (notes.isEmpty) return null;
    final seen = <String>{};
    final parts = <String>[];
    for (final note in notes) {
      final trimmed = note.note.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        parts.add(trimmed);
      }
    }
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  Map<String, String> _buildSocialHandles(List<SocialMedia> socialMedias) {
    if (socialMedias.isEmpty) return const <String, String>{};
    final handles = <String, String>{};
    for (final social in socialMedias) {
      final handle = social.userName.trim();
      if (handle.isEmpty) continue;

      String? label;
      if (social.label == SocialMediaLabel.custom) {
        final custom = social.customLabel.trim();
        if (custom.isNotEmpty) {
          label = custom;
        }
      } else if (social.label != SocialMediaLabel.other) {
        label = social.label.name;
      } else if (social.customLabel.trim().isNotEmpty) {
        label = social.customLabel.trim();
      }

      if (label == null || label.isEmpty) continue;
      final key = label.toLowerCase();
      handles.putIfAbsent(key, () => handle);
    }
    return handles;
  }

  List<geogram.ContactDateReminder> _buildDateReminders(List<Event> events) {
    if (events.isEmpty) return const <geogram.ContactDateReminder>[];
    final reminders = <geogram.ContactDateReminder>[];
    final seen = <String>{};

    for (final event in events) {
      if (event.month < 1 || event.month > 12 || event.day < 1 || event.day > 31) {
        continue;
      }

      final type = _eventLabelToReminderType(event.label);
      final label = event.label == EventLabel.custom && event.customLabel.trim().isNotEmpty
          ? event.customLabel.trim()
          : null;
      final key = '${type.name}|${label ?? ''}|${event.month}|${event.day}|${event.year ?? ''}';
      if (!seen.add(key)) continue;

      reminders.add(geogram.ContactDateReminder(
        type: type,
        label: label,
        month: event.month,
        day: event.day,
        year: event.year,
      ));
    }

    return reminders;
  }

  geogram.ContactDateReminderType _eventLabelToReminderType(EventLabel label) {
    switch (label) {
      case EventLabel.birthday:
        return geogram.ContactDateReminderType.birthday;
      case EventLabel.anniversary:
        return geogram.ContactDateReminderType.married;
      case EventLabel.other:
      case EventLabel.custom:
        return geogram.ContactDateReminderType.other;
    }
  }

  List<String> _dedupeByNormalized(
    Iterable<String> values,
    String Function(String value) normalize,
  ) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = normalize(trimmed);
      if (key.isEmpty) continue;
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Mark duplicates in the list based on existing Geogram contacts
  Future<void> markDuplicates(
    List<DeviceContactInfo> deviceContacts,
    List<geogram.Contact> existingContacts,
  ) async {
    final existingNames = <String>{};
    final existingEmails = <String>{};
    final existingPhones = <String>{};

    for (final contact in existingContacts) {
      existingNames.add(contact.displayName.toLowerCase());
      for (final email in contact.emails) {
        final trimmed = email.trim();
        if (trimmed.isNotEmpty) {
          existingEmails.add(trimmed.toLowerCase());
        }
      }
      for (final phone in contact.phones) {
        final normalized = _normalizePhone(phone);
        if (normalized.isNotEmpty) {
          existingPhones.add(normalized);
        }
      }
    }

    for (final device in deviceContacts) {
      final nameMatch = existingNames.contains(device.displayName.toLowerCase());
      final emailMatch = device.emails.any((email) => existingEmails.contains(email.toLowerCase()));
      final phoneMatch = device.phones.any((phone) => existingPhones.contains(_normalizePhone(phone)));
      device.isDuplicate = nameMatch || emailMatch || phoneMatch;
      if (device.isDuplicate) {
        device.selected = false; // Don't pre-select duplicates
      }
    }
  }

  /// Normalize phone for comparison
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  NostrKeys _generateUniqueKeys(Set<String> usedCallsigns, Set<String> usedNpubs) {
    while (true) {
      final keys = NostrKeyGenerator.generateKeyPair();
      if (usedCallsigns.add(keys.callsign) && usedNpubs.add(keys.npub)) {
        return keys;
      }
    }
  }

  String _detectImageExtension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x39 || bytes[4] == 0x37) &&
        bytes[5] == 0x61) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
  }

  /// Import selected contacts
  Future<ImportResult> importContacts({
    required List<DeviceContactInfo> contacts,
    required String appPath,
    required String? groupPath,
    List<geogram.Contact>? existingContacts,
    required Function(int imported, int total) onProgress,
  }) async {
    final contactService = ContactService();
    await contactService.initializeApp(appPath);

    final existing = existingContacts ?? await contactService.loadAllContactsRecursively();
    final usedCallsigns = existing.map((contact) => contact.callsign).toSet();
    final usedNpubs = <String>{};
    for (final contact in existing) {
      final npub = contact.npub;
      if (npub != null && npub.isNotEmpty) {
        usedNpubs.add(npub);
      }
    }

    int imported = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    final selectedContacts = contacts.where((c) => c.selected && !c.isDuplicate).toList();
    final total = selectedContacts.length;

    for (var i = 0; i < selectedContacts.length; i++) {
      final device = selectedContacts[i];
      onProgress(i + 1, total);

      try {
        final hydrated = await _hydrateDeviceContact(device);

        // Generate temporary NOSTR identity
        final keys = _generateUniqueKeys(usedCallsigns, usedNpubs);

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
        if (hydrated.photo != null && hydrated.photo!.isNotEmpty) {
          final extension = _detectImageExtension(hydrated.photo!);
          profilePicture = await contactService.saveProfilePictureFromBytes(
            keys.callsign,
            hydrated.photo!,
            extension,
          );
        }

        // Create Geogram contact
        final contact = geogram.Contact(
          displayName: hydrated.displayName,
          callsign: keys.callsign,
          npub: keys.npub,
          created: timestamp,
          firstSeen: timestamp,
          emails: hydrated.emails,
          phones: hydrated.phones,
          addresses: hydrated.addresses,
          websites: hydrated.websites,
          socialHandles: hydrated.socialHandles,
          dateReminders: hydrated.dateReminders,
          notes: hydrated.note ?? '',
          profilePicture: profilePicture,
          isTemporaryIdentity: true,
          temporaryNsec: keys.nsec,
          tags: ['imported'],
          groupPath: groupPath,
        );

        // Save contact
        final error = await contactService.saveContact(
          contact,
          groupPath: groupPath,
          skipDuplicateCheck: true,
          skipFastJsonRebuild: true,
        );

        if (error != null) {
          failed++;
          errors.add('${hydrated.displayName}: $error');
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

    if (imported > 0) {
      await contactService.rebuildFastJson();
    }

    LogService().log('ContactImport: Complete - imported=$imported, skipped=$skipped, failed=$failed');

    return ImportResult(
      importedCount: imported,
      skippedDuplicates: skipped,
      failedCount: failed,
      errors: errors,
    );
  }
}
