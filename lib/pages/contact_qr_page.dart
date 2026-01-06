/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/contact.dart';
import '../models/event.dart';
import '../services/contact_service.dart';
import '../services/contact_qr_service.dart' as qr_service;
import '../services/event_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';
import '../services/storage_config.dart';
import '../util/geolocation_utils.dart';
import '../widgets/qr_share_receive_widget.dart';

/// Combined QR code page for contacts with Send/Receive tabs
///
/// This page provides a tabbed interface for:
/// - **Send tab**: Select a contact and choose which fields to share via QR
/// - **Receive tab**: Scan QR codes from other devices to import contacts
class ContactQrPage extends StatefulWidget {
  final ContactService contactService;
  final I18nService i18n;

  /// Optional pre-selected contact for sharing
  final Contact? initialContact;

  /// Initial tab (0 = Send, 1 = Receive)
  final int initialTab;

  const ContactQrPage({
    super.key,
    required this.contactService,
    required this.i18n,
    this.initialContact,
    this.initialTab = 0,
  });

  @override
  State<ContactQrPage> createState() => _ContactQrPageState();
}

class _ContactQrPageState extends State<ContactQrPage>
    with SingleTickerProviderStateMixin {
  final qr_service.ContactQrService _qrService = qr_service.ContactQrService();
  late TabController _tabController;

  Contact? _selectedContact;
  List<Contact> _contacts = [];
  bool _isLoading = true;

  // Send tab state
  List<QrShareField> _fields = [];
  String _qrData = '';
  int _qrSize = 0;
  QrSizeStatus _sizeStatus = QrSizeStatus.ok;

  // Receive tab state
  bool _isScanning = false;
  bool _hasScanned = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _scanError;

  // Exchange metadata state (optional fields for QR sharing)
  String? _shareNote;
  double? _shareLatitude;
  double? _shareLongitude;
  String? _shareEventId;
  String? _shareEventName;
  bool _exchangeExpanded = false;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(_onTabChanged);
    _selectedContact = widget.initialContact;
    _loadContacts();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_isScanning && !_permissionDenied) {
      _startScanner();
    } else if (_tabController.index == 0) {
      _stopScanner();
    }
  }

  Future<void> _loadContacts() async {
    final contacts = <Contact>[];
    await for (final contact
        in widget.contactService.loadAllContactsStreamFast()) {
      contacts.add(contact);
    }
    final sorted = await widget.contactService.sortContactsByPopularity(contacts);

    setState(() {
      _contacts = sorted;
      _isLoading = false;
    });

    // If we have an initial contact, load its full data
    if (_selectedContact != null) {
      final fullContact = await widget.contactService.loadContact(
        _selectedContact!.callsign,
        groupPath: _selectedContact!.groupPath,
      );
      if (fullContact != null && mounted) {
        setState(() {
          _selectedContact = fullContact;
        });
      }
      _initializeFields();
    }
  }

  void _initializeFields() {
    if (_selectedContact == null) return;
    _fields = _getContactFields(_selectedContact!);
    _updateQrData();
  }

  List<QrShareField> _getContactFields(Contact contact) {
    final fields = <QrShareField>[];

    fields.add(QrShareField(
      id: 'displayName',
      label: widget.i18n.t('field_display_name'),
      icon: Icons.person,
      isRequired: true,
      estimatedSize: contact.displayName.length + 20,
    ));

    fields.add(QrShareField(
      id: 'callsign',
      label: widget.i18n.t('field_callsign'),
      icon: Icons.tag,
      isRequired: true,
      estimatedSize: contact.callsign.length + 15,
    ));

    if (contact.npub != null && contact.npub!.isNotEmpty) {
      fields.add(QrShareField(
        id: 'npub',
        label: widget.i18n.t('field_npub'),
        icon: Icons.key,
        isRequired: true,
        estimatedSize: contact.npub!.length + 10,
      ));
    }

    if (contact.emails.isNotEmpty) {
      fields.add(QrShareField(
        id: 'emails',
        label: widget.i18n.t('field_emails'),
        icon: Icons.email,
        estimatedSize: _estimateListSize(contact.emails),
        subFields: contact.emails
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'email_${e.key}',
                  value: e.value,
                  parentId: 'emails',
                ))
            .toList(),
      ));
    }

    if (contact.phones.isNotEmpty) {
      fields.add(QrShareField(
        id: 'phones',
        label: widget.i18n.t('field_phones'),
        icon: Icons.phone,
        estimatedSize: _estimateListSize(contact.phones),
        subFields: contact.phones
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'phone_${e.key}',
                  value: e.value,
                  parentId: 'phones',
                ))
            .toList(),
      ));
    }

    if (contact.addresses.isNotEmpty) {
      fields.add(QrShareField(
        id: 'addresses',
        label: widget.i18n.t('field_addresses'),
        icon: Icons.location_on,
        estimatedSize: _estimateListSize(contact.addresses),
        subFields: contact.addresses
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'address_${e.key}',
                  value: e.value.length > 50
                      ? '${e.value.substring(0, 50)}...'
                      : e.value,
                  parentId: 'addresses',
                ))
            .toList(),
      ));
    }

    if (contact.websites.isNotEmpty) {
      fields.add(QrShareField(
        id: 'websites',
        label: widget.i18n.t('field_websites'),
        icon: Icons.language,
        estimatedSize: _estimateListSize(contact.websites),
        subFields: contact.websites
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'website_${e.key}',
                  value: e.value,
                  parentId: 'websites',
                ))
            .toList(),
      ));
    }

    if (contact.locations.isNotEmpty) {
      fields.add(QrShareField(
        id: 'locations',
        label: widget.i18n.t('field_locations'),
        icon: Icons.place,
        estimatedSize: contact.locations.length * 50,
      ));
    }

    if (contact.socialHandles.isNotEmpty) {
      final handles = contact.socialHandles.entries.toList();
      fields.add(QrShareField(
        id: 'socialHandles',
        label: widget.i18n.t('field_social_handles'),
        icon: Icons.share,
        estimatedSize: handles.fold(
            0, (sum, e) => sum + e.key.length + e.value.length + 10),
        subFields: handles
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'social_${e.key}',
                  value: '${e.value.key}: ${e.value.value}',
                  parentId: 'socialHandles',
                ))
            .toList(),
      ));
    }

    if (contact.tags.isNotEmpty) {
      fields.add(QrShareField(
        id: 'tags',
        label: widget.i18n.t('field_tags'),
        icon: Icons.label,
        estimatedSize: _estimateListSize(contact.tags),
        subFields: contact.tags
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'tag_${e.key}',
                  value: e.value,
                  parentId: 'tags',
                ))
            .toList(),
      ));
    }

    if (contact.radioCallsigns.isNotEmpty) {
      fields.add(QrShareField(
        id: 'radioCallsigns',
        label: widget.i18n.t('field_radio_callsigns'),
        icon: Icons.radio,
        estimatedSize: _estimateListSize(contact.radioCallsigns),
        subFields: contact.radioCallsigns
            .asMap()
            .entries
            .map((e) => QrShareSubField(
                  id: 'radio_${e.key}',
                  value: e.value,
                  parentId: 'radioCallsigns',
                ))
            .toList(),
      ));
    }

    if (contact.notes.isNotEmpty) {
      fields.add(QrShareField(
        id: 'notes',
        label: widget.i18n.t('field_notes'),
        icon: Icons.note,
        estimatedSize: contact.notes.length + 10,
      ));
    }

    return fields;
  }

  int _estimateListSize(List<String> list) {
    return list.fold(10, (sum, item) => sum + item.length + 3);
  }

  void _updateQrData() {
    if (_selectedContact == null) return;
    _qrData = _encodeContact(_selectedContact!, _fields);
    _qrSize = utf8.encode(_qrData).length;
    _sizeStatus = _getSizeStatus(_qrSize);
    setState(() {});
  }

  QrSizeStatus _getSizeStatus(int bytes) {
    if (bytes > 1500) return QrSizeStatus.tooLarge;
    if (bytes > 1000) return QrSizeStatus.warning;
    return QrSizeStatus.ok;
  }

  String _encodeContact(Contact contact, List<QrShareField> fields) {
    final json = <String, dynamic>{
      'geogram_contact': '1.0',
      'displayName': contact.displayName,
      'callsign': contact.callsign,
    };

    for (final field in fields) {
      if (!field.isSelected) continue;

      switch (field.id) {
        case 'npub':
          if (contact.npub != null) json['npub'] = contact.npub;
          break;
        case 'emails':
          final selected = _getSelectedSubFieldValues(field, contact.emails);
          if (selected.isNotEmpty) json['emails'] = selected;
          break;
        case 'phones':
          final selected = _getSelectedSubFieldValues(field, contact.phones);
          if (selected.isNotEmpty) json['phones'] = selected;
          break;
        case 'addresses':
          final selected = _getSelectedSubFieldValues(field, contact.addresses);
          if (selected.isNotEmpty) json['addresses'] = selected;
          break;
        case 'websites':
          final selected = _getSelectedSubFieldValues(field, contact.websites);
          if (selected.isNotEmpty) json['websites'] = selected;
          break;
        case 'locations':
          json['locations'] = contact.locations.map((l) => l.toJson()).toList();
          break;
        case 'socialHandles':
          final selected =
              _getSelectedSocialHandles(field, contact.socialHandles);
          if (selected.isNotEmpty) json['socialHandles'] = selected;
          break;
        case 'tags':
          final selected = _getSelectedSubFieldValues(field, contact.tags);
          if (selected.isNotEmpty) json['tags'] = selected;
          break;
        case 'radioCallsigns':
          final selected =
              _getSelectedSubFieldValues(field, contact.radioCallsigns);
          if (selected.isNotEmpty) json['radioCallsigns'] = selected;
          break;
        case 'notes':
          json['notes'] = contact.notes;
          break;
      }
    }

    // Add optional exchange metadata
    if (_shareNote != null && _shareNote!.isNotEmpty) {
      json['exchange_note'] = _shareNote;
    }
    if (_shareLatitude != null && _shareLongitude != null) {
      json['exchange_lat'] = _shareLatitude;
      json['exchange_lon'] = _shareLongitude;
    }
    if (_shareEventId != null && _shareEventId!.isNotEmpty) {
      json['exchange_event'] = _shareEventId;
    }

    return jsonEncode(json);
  }

  List<String> _getSelectedSubFieldValues(
      QrShareField field, List<String> values) {
    if (field.subFields == null) return values;

    final selected = <String>[];
    for (int i = 0; i < values.length && i < field.subFields!.length; i++) {
      if (field.subFields![i].isSelected) {
        selected.add(values[i]);
      }
    }
    return selected;
  }

  Map<String, String> _getSelectedSocialHandles(
      QrShareField field, Map<String, String> handles) {
    if (field.subFields == null) return handles;

    final entries = handles.entries.toList();
    final selected = <String, String>{};
    for (int i = 0; i < entries.length && i < field.subFields!.length; i++) {
      if (field.subFields![i].isSelected) {
        selected[entries[i].key] = entries[i].value;
      }
    }
    return selected;
  }

  void _toggleField(QrShareField field) {
    if (field.isRequired) return;
    setState(() {
      field.isSelected = !field.isSelected;
      if (field.subFields != null) {
        for (final subField in field.subFields!) {
          subField.isSelected = field.isSelected;
        }
      }
      _updateQrData();
    });
  }

  void _toggleSubField(QrShareField field, QrShareSubField subField) {
    setState(() {
      subField.isSelected = !subField.isSelected;
      field.isSelected = field.subFields!.any((sf) => sf.isSelected);
      _updateQrData();
    });
  }

  void _selectAll() {
    setState(() {
      for (final field in _fields) {
        field.isSelected = true;
        if (field.subFields != null) {
          for (final subField in field.subFields!) {
            subField.isSelected = true;
          }
        }
      }
      _updateQrData();
    });
  }

  void _selectMinimal() {
    setState(() {
      for (final field in _fields) {
        field.isSelected = field.isRequired;
        if (field.subFields != null) {
          for (final subField in field.subFields!) {
            subField.isSelected = field.isRequired;
          }
        }
      }
      _updateQrData();
    });
  }

  // Exchange metadata methods
  Widget _buildExchangeDetailsSection(ThemeData theme) {
    final hasMetadata = _shareNote?.isNotEmpty == true ||
        _shareLatitude != null ||
        _shareEventId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(
          children: [
            // Expandable header
            InkWell(
              onTap: () => setState(() => _exchangeExpanded = !_exchangeExpanded),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: hasMetadata
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.i18n.t('exchange_details'),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            widget.i18n.t('exchange_details_hint'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasMetadata)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _countActiveMetadata().toString(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      _exchangeExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // Expandable content
            if (_exchangeExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Note field
                    TextField(
                      decoration: InputDecoration(
                        labelText: widget.i18n.t('note'),
                        hintText: widget.i18n.t('exchange_note_hint'),
                        prefixIcon: const Icon(Icons.note),
                        border: const OutlineInputBorder(),
                        suffixIcon: _shareNote?.isNotEmpty == true
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() => _shareNote = null);
                                  _updateQrData();
                                },
                              )
                            : null,
                      ),
                      maxLines: 2,
                      onChanged: (value) {
                        setState(() => _shareNote = value.isEmpty ? null : value);
                        _updateQrData();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Location row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _gettingLocation ? null : _captureLocation,
                            icon: _gettingLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _shareLatitude != null
                                        ? Icons.location_on
                                        : Icons.location_searching,
                                  ),
                            label: Text(
                              _shareLatitude != null
                                  ? '${_shareLatitude!.toStringAsFixed(4)}, ${_shareLongitude!.toStringAsFixed(4)}'
                                  : widget.i18n.t('add_location'),
                            ),
                          ),
                        ),
                        if (_shareLatitude != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _shareLatitude = null;
                                _shareLongitude = null;
                              });
                              _updateQrData();
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Event row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectEvent,
                            icon: Icon(
                              _shareEventId != null
                                  ? Icons.event
                                  : Icons.event_available,
                            ),
                            label: Text(
                              _shareEventName ?? widget.i18n.t('select_event'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (_shareEventId != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _shareEventId = null;
                                _shareEventName = null;
                              });
                              _updateQrData();
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _countActiveMetadata() {
    int count = 0;
    if (_shareNote?.isNotEmpty == true) count++;
    if (_shareLatitude != null) count++;
    if (_shareEventId != null) count++;
    return count;
  }

  Future<void> _captureLocation() async {
    setState(() => _gettingLocation = true);

    try {
      final result = await GeolocationUtils.getCurrentLocation(
        timeout: const Duration(seconds: 10),
      );

      if (result != null && mounted) {
        setState(() {
          _shareLatitude = result.latitude;
          _shareLongitude = result.longitude;
        });
        _updateQrData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.i18n.t('location_unavailable')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _gettingLocation = false);
      }
    }
  }

  Future<void> _selectEvent() async {
    final storageConfig = StorageConfig();
    if (!storageConfig.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('no_events_found'))),
      );
      return;
    }

    final events = await EventService().getAllEventsGlobal(storageConfig.baseDir);

    if (!mounted) return;

    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('no_events_found'))),
      );
      return;
    }

    // Sort by date descending (newest first)
    events.sort((a, b) => (b.startDate ?? '').compareTo(a.startDate ?? ''));

    final selected = await showModalBottomSheet<Event>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EventPickerSheet(
        events: events,
        i18n: widget.i18n,
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _shareEventId = selected.id;
        _shareEventName = selected.title;
      });
      _updateQrData();
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(widget.i18n.t('copied_to_clipboard', params: ['JSON'])),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _getSizeColor() {
    switch (_sizeStatus) {
      case QrSizeStatus.ok:
        return Colors.green;
      case QrSizeStatus.warning:
        return Colors.orange;
      case QrSizeStatus.tooLarge:
        return Colors.red;
    }
  }

  IconData _getSizeIcon() {
    switch (_sizeStatus) {
      case QrSizeStatus.ok:
        return Icons.check_circle;
      case QrSizeStatus.warning:
        return Icons.warning;
      case QrSizeStatus.tooLarge:
        return Icons.error;
    }
  }

  String _getSizeMessage() {
    switch (_sizeStatus) {
      case QrSizeStatus.ok:
        return widget.i18n.t('qr_size_ok');
      case QrSizeStatus.warning:
        return widget.i18n.t('qr_size_warning');
      case QrSizeStatus.tooLarge:
        return widget.i18n.t('qr_size_too_large');
    }
  }

  // Scanner methods
  Future<void> _startScanner() async {
    // flutter_zxing supports: Android, iOS, macOS
    // Web and Linux/Windows desktop don't have camera support via ZXing
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      setState(() {
        _scanError = widget.i18n.t('camera_not_supported');
      });
      return;
    }

    final status = await Permission.camera.status;

    if (status.isGranted) {
      _initScanner();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionDenied = true;
        _permissionPermanentlyDenied = true;
      });
    } else {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        _initScanner();
      } else {
        setState(() {
          _permissionDenied = true;
          _permissionPermanentlyDenied = result.isPermanentlyDenied;
        });
      }
    }
  }

  void _initScanner() {
    setState(() {
      _isScanning = true;
      _hasScanned = false;
      _scanError = null;
    });
  }

  void _stopScanner() {
    setState(() {
      _isScanning = false;
    });
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
      _scanError = null;
    });
  }

  void _onScan(Code code) {
    if (_hasScanned) return;
    if (!code.isValid) return;

    final value = code.text;
    if (value == null) return;

    final result = _qrService.decodeContactWithMetadata(value);
    if (result != null) {
      setState(() {
        _hasScanned = true;
      });
      _handleScannedContact(result);
    }
  }

  Future<void> _handleScannedContact(qr_service.QrContactResult result) async {
    final shouldSave = await _showContactPreview(result.contact, result);
    if (shouldSave == true) {
      final success = await _saveContact(result);
      if (success && mounted) {
        _showSuccess(widget.i18n.t('saved_successfully'));
        Navigator.pop(context, true);
      } else {
        _showError(widget.i18n.t('save_failed'));
        _resetScanner();
      }
    } else {
      _resetScanner();
    }
  }

  Future<bool> _saveContact(qr_service.QrContactResult result) async {
    try {
      final contact = result.contact;
      final existing =
          await widget.contactService.getContactByCallsign(contact.callsign);

      String savedCallsign = contact.callsign;

      if (existing != null) {
        final action = await _showDuplicateDialog(existing, contact);

        if (action == 'update') {
          // Keep existing firstSeen when updating
          final updated = existing.copyWith(
            displayName: contact.displayName,
            npub: contact.npub ?? existing.npub,
            emails:
                contact.emails.isNotEmpty ? contact.emails : existing.emails,
            phones:
                contact.phones.isNotEmpty ? contact.phones : existing.phones,
            addresses: contact.addresses.isNotEmpty
                ? contact.addresses
                : existing.addresses,
            websites: contact.websites.isNotEmpty
                ? contact.websites
                : existing.websites,
            locations: contact.locations.isNotEmpty
                ? contact.locations
                : existing.locations,
            socialHandles: contact.socialHandles.isNotEmpty
                ? contact.socialHandles
                : existing.socialHandles,
            tags: {...existing.tags, ...contact.tags}.toList(),
            radioCallsigns: contact.radioCallsigns.isNotEmpty
                ? contact.radioCallsigns
                : existing.radioCallsigns,
          );
          await widget.contactService.saveContact(updated);
          savedCallsign = updated.callsign;
        } else if (action == 'new') {
          final newCallsign = await widget.contactService
              .generateUniqueCallsign(contact.displayName);
          final newContact = contact.copyWith(callsign: newCallsign);
          await widget.contactService.saveContact(newContact);
          savedCallsign = newCallsign;
        } else {
          return false;
        }
      } else {
        // New contact - firstSeen is already set by decodeContactWithMetadata
        await widget.contactService.saveContact(contact);
      }

      // Add history entry to log the QR exchange
      await _addExchangeHistoryEntry(savedCallsign, result);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Add a history entry to log the QR code exchange
  Future<void> _addExchangeHistoryEntry(
    String callsign,
    qr_service.QrContactResult result,
  ) async {
    try {
      final profile = ProfileService().getProfile();
      final author = profile.callsign;

      // Build content message
      String content = result.hasNote
          ? result.exchangeNote!
          : widget.i18n.t('contact_received_via_qr');

      final entry = ContactHistoryEntry.now(
        author: author,
        content: content,
        type: ContactHistoryEntryType.message,
        latitude: result.exchangeLat,
        longitude: result.exchangeLon,
        eventReference: result.exchangeEventId,
        metadata: {
          'qr_action': 'received',
          'qr_from': result.contact.callsign,
        },
      );

      await widget.contactService.addHistoryEntry(callsign, entry);
    } catch (e) {
      // Don't fail the save if history entry fails
    }
  }

  Future<bool?> _showContactPreview(Contact contact, [qr_service.QrContactResult? result]) {
    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(widget.i18n.t('contact_scanned')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    contact.displayName.isNotEmpty
                        ? contact.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  contact.displayName,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  contact.callsign,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const Divider(),
              if (contact.npub != null)
                _buildPreviewRow(
                    Icons.key, 'NPUB', '${contact.npub!.substring(0, 16)}...'),
              if (contact.emails.isNotEmpty)
                _buildPreviewRow(Icons.email, widget.i18n.t('field_emails'),
                    '${contact.emails.length}'),
              if (contact.phones.isNotEmpty)
                _buildPreviewRow(Icons.phone, widget.i18n.t('field_phones'),
                    '${contact.phones.length}'),
              if (contact.addresses.isNotEmpty)
                _buildPreviewRow(Icons.location_on,
                    widget.i18n.t('field_addresses'), '${contact.addresses.length}'),
              if (contact.websites.isNotEmpty)
                _buildPreviewRow(Icons.language, widget.i18n.t('field_websites'),
                    '${contact.websites.length}'),
              if (contact.tags.isNotEmpty)
                _buildPreviewRow(Icons.label, widget.i18n.t('field_tags'),
                    contact.tags.join(', ')),
              // Show exchange metadata if present
              if (result != null && result.hasExchangeMetadata) ...[
                const Divider(),
                Text(
                  widget.i18n.t('exchange_details'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                if (result.hasNote)
                  _buildPreviewRow(Icons.note, widget.i18n.t('note'),
                      result.exchangeNote!),
                if (result.hasLocation)
                  _buildPreviewRow(Icons.place, widget.i18n.t('location'),
                      '${result.exchangeLat!.toStringAsFixed(4)}, ${result.exchangeLon!.toStringAsFixed(4)}'),
                if (result.hasEvent)
                  _buildPreviewRow(Icons.event, widget.i18n.t('event'),
                      result.exchangeEventId!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save),
            label: Text(widget.i18n.t('save')),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showDuplicateDialog(Contact existing, Contact scanned) {
    final theme = Theme.of(context);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.i18n.t('contact_already_exists'))),
          ],
        ),
        content: Text(
          'A contact with callsign "${scanned.callsign}" already exists (${existing.displayName}). What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(widget.i18n.t('cancel')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: Text(widget.i18n.t('save_as_new')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(widget.i18n.t('update_existing')),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _selectContact() async {
    final contact = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContactPickerSheet(
        contacts: _contacts,
        i18n: widget.i18n,
      ),
    );

    if (contact != null) {
      // Load the full contact data (the picker may return placeholder contacts)
      final fullContact = await widget.contactService.loadContact(
        contact.callsign,
        groupPath: contact.groupPath,
      );

      if (fullContact != null && mounted) {
        setState(() {
          _selectedContact = fullContact;
          _initializeFields();
        });
      } else if (mounted) {
        // Fallback to the contact we have if loading fails
        setState(() {
          _selectedContact = contact;
          _initializeFields();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('qr_code')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.qr_code),
              text: widget.i18n.t('send'),
            ),
            Tab(
              icon: const Icon(Icons.qr_code_scanner),
              text: widget.i18n.t('receive'),
            ),
          ],
        ),
        actions: [
          if (_tabController.index == 0 && _selectedContact != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyToClipboard,
              tooltip: widget.i18n.t('copy_to_clipboard', params: ['JSON']),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSendTab(),
                _buildReceiveTab(),
              ],
            ),
    );
  }

  Widget _buildSendTab() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Contact selector card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: InkWell(
                onTap: _selectContact,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        radius: 24,
                        child: _selectedContact != null
                            ? Text(
                                _selectedContact!.displayName.isNotEmpty
                                    ? _selectedContact!.displayName[0]
                                        .toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontSize: 20,
                                ),
                              )
                            : Icon(Icons.person_add,
                                color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedContact?.displayName ??
                                  widget.i18n.t('select_contact'),
                              style: theme.textTheme.titleMedium,
                            ),
                            if (_selectedContact != null)
                              Text(
                                _selectedContact!.callsign,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else
                              Text(
                                widget.i18n.t('no_data_to_share'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_selectedContact != null) ...[
            // QR Code Display
            Container(
              padding: const EdgeInsets.all(24),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Size indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getSizeColor().withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _getSizeColor().withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getSizeIcon(), size: 18, color: _getSizeColor()),
                        const SizedBox(width: 8),
                        Text(
                          widget.i18n.t('qr_size', params: [_qrSize.toString()]),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _getSizeColor(),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '- ${_getSizeMessage()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _getSizeColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Exchange details (optional metadata)
            _buildExchangeDetailsSection(theme),

            // Quick actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectMinimal,
                      icon: const Icon(Icons.minimize, size: 18),
                      label: Text(widget.i18n.t('minimal')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectAll,
                      icon: const Icon(Icons.select_all, size: 18),
                      label: Text(widget.i18n.t('select_all')),
                    ),
                  ),
                ],
              ),
            ),

            // Field selection header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.checklist,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.i18n.t('select_fields_to_share'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // Field selection list
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _fields.length,
              itemBuilder: (context, index) {
                final field = _fields[index];
                return _buildFieldTile(field);
              },
            ),

            const SizedBox(height: 24),
          ] else
            // Empty state
            Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.i18n.t('no_data_to_share'),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldTile(QrShareField field) {
    final theme = Theme.of(context);
    final hasSubFields =
        field.subFields != null && field.subFields!.isNotEmpty;

    return Column(
      children: [
        CheckboxListTile(
          value: field.isSelected,
          onChanged: field.isRequired ? null : (value) => _toggleField(field),
          title: Row(
            children: [
              Icon(
                field.icon,
                size: 20,
                color: field.isRequired
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  field.label,
                  style: TextStyle(
                    fontWeight: field.isRequired ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (hasSubFields)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${field.subFields!.where((sf) => sf.isSelected).length}/${field.subFields!.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: field.isRequired
              ? Text(
                  widget.i18n.t('field_required'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              : null,
          secondary: field.isRequired
              ? Icon(Icons.lock, size: 18, color: theme.colorScheme.primary)
              : null,
        ),

        // Sub-fields
        if (hasSubFields && field.isSelected)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Column(
              children: field.subFields!.map((subField) {
                return CheckboxListTile(
                  value: subField.isSelected,
                  onChanged: (value) => _toggleSubField(field, subField),
                  title: Text(
                    subField.value,
                    style: theme.textTheme.bodyMedium,
                  ),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildReceiveTab() {
    final theme = Theme.of(context);

    if (_scanError != null) {
      return _buildErrorView(theme, _scanError!);
    }

    if (_permissionDenied) {
      return _buildPermissionDeniedView(theme);
    }

    if (!_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(widget.i18n.t('initializing_camera')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview with ZXing scanner
        ReaderWidget(
          onScan: _onScan,
          isMultiScan: false,
          showFlashlight: false,
          showToggleCamera: false,
          showGallery: false,
          tryHarder: true,
          tryInverted: true,
        ),

        // Scanning overlay
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Corner decorations
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: CustomPaint(
              painter: _CornersPainter(color: theme.colorScheme.primary),
            ),
          ),
        ),

        // Instructions
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    widget.i18n.t('scanning_qr'),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _permissionPermanentlyDenied
                  ? widget.i18n.t('camera_permission_denied')
                  : widget.i18n.t('camera_permission_required'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_permissionPermanentlyDenied)
              FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: Text(widget.i18n.t('open_settings')),
              )
            else
              FilledButton.icon(
                onPressed: _startScanner,
                icon: const Icon(Icons.refresh),
                label: Text(widget.i18n.t('try_again')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for corner decorations
class _CornersPainter extends CustomPainter {
  final Color color;

  _CornersPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 16.0;

    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, cornerLength),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(cornerLength, size.height),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(
            size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Contact picker bottom sheet
class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  final I18nService i18n;

  const _ContactPickerSheet({
    required this.contacts,
    required this.i18n,
  });

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Contact> _filteredContacts = [];

  @override
  void initState() {
    super.initState();
    _filteredContacts = widget.contacts;
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredContacts = widget.contacts;
      } else {
        _filteredContacts = widget.contacts.where((c) {
          return c.displayName.toLowerCase().contains(query) ||
              c.callsign.toLowerCase().contains(query) ||
              (c.groupPath?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.i18n.t('select_contact'),
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.i18n.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            Expanded(
              child: _filteredContacts.isEmpty
                  ? Center(
                      child: Text(widget.i18n.t('no_contacts_found')),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = _filteredContacts[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              contact.displayName.isNotEmpty
                                  ? contact.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(contact.displayName),
                          subtitle: Text(
                            contact.groupPath?.isNotEmpty == true
                                ? '${contact.callsign} • ${contact.groupPath}'
                                : contact.callsign,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          onTap: () => Navigator.pop(context, contact),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Event picker bottom sheet
class _EventPickerSheet extends StatefulWidget {
  final List<Event> events;
  final I18nService i18n;

  const _EventPickerSheet({
    required this.events,
    required this.i18n,
  });

  @override
  State<_EventPickerSheet> createState() => _EventPickerSheetState();
}

class _EventPickerSheetState extends State<_EventPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Event> _filteredEvents = [];

  @override
  void initState() {
    super.initState();
    _filteredEvents = widget.events;
    _searchController.addListener(_filterEvents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterEvents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredEvents = widget.events;
      } else {
        _filteredEvents = widget.events.where((e) {
          return e.title.toLowerCase().contains(query) ||
              e.content.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.i18n.t('select_event'),
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.i18n.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            Expanded(
              child: _filteredEvents.isEmpty
                  ? Center(
                      child: Text(widget.i18n.t('no_events_found')),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredEvents.length,
                      itemBuilder: (context, index) {
                        final event = _filteredEvents[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.event,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(event.title),
                          subtitle: event.startDate != null
                              ? Text(
                                  event.startDate!,
                                  style: theme.textTheme.bodySmall,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, event),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
