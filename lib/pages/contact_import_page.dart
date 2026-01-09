/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contact.dart' as geogram;
import '../services/contact_import_service.dart';
import '../services/contact_service.dart';
import '../services/i18n_service.dart';

/// Page for importing contacts from device address book
class ContactImportPage extends StatefulWidget {
  final String collectionPath;
  final String? groupPath;

  const ContactImportPage({
    Key? key,
    required this.collectionPath,
    this.groupPath,
  }) : super(key: key);

  @override
  State<ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends State<ContactImportPage> {
  final ContactImportService _importService = ContactImportService();
  final ContactService _contactService = ContactService();
  final I18nService _i18n = I18nService();

  List<DeviceContactInfo> _deviceContacts = [];
  List<geogram.Contact> _existingContacts = [];
  bool _isLoading = true;
  bool _isImporting = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _errorMessage;
  int _importProgress = 0;
  int _importTotal = 0;

  @override
  void initState() {
    super.initState();
    _checkPlatformAndLoad();
  }

  Future<void> _checkPlatformAndLoad() async {
    // Check if we're on Android
    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _isLoading = false;
        _errorMessage = _i18n.t('android_only_feature');
      });
      return;
    }

    await _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    setState(() {
      _isLoading = true;
      _deviceContacts = [];
      _existingContacts = [];
      _permissionDenied = false;
      _permissionPermanentlyDenied = false;
      _errorMessage = null;
    });

    // Check if permission is already granted
    final hasPermission = await _importService.hasContactsPermission();

    if (hasPermission) {
      await _loadContacts();
    } else {
      // Request permission
      final granted = await _importService.requestContactsPermission();

      if (granted) {
        await _loadContacts();
      } else {
        // Check if permanently denied
        final permanentlyDenied = await _importService.isPermissionPermanentlyDenied();

        setState(() {
          _isLoading = false;
          _permissionDenied = true;
          _permissionPermanentlyDenied = permanentlyDenied;
        });
      }
    }
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Initialize contact service to load existing contacts
      await _contactService.initializeCollection(widget.collectionPath);

      // Fetch device contacts
      final deviceContacts = await _importService.fetchDeviceContacts();

      if (deviceContacts.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = _i18n.t('no_device_contacts');
        });
        return;
      }

      // Load existing Geogram contacts for duplicate detection
      final existingContacts = await _contactService.loadAllContactsRecursively();

      // Mark duplicates
      await _importService.markDuplicates(deviceContacts, existingContacts);

      // Sort: non-duplicates first, then by name
      deviceContacts.sort((a, b) {
        if (a.isDuplicate != b.isDuplicate) {
          return a.isDuplicate ? 1 : -1;
        }
        return a.displayName.compareTo(b.displayName);
      });

      setState(() {
        _deviceContacts = deviceContacts;
        _existingContacts = existingContacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading contacts: $e';
      });
    }
  }

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      for (var contact in _deviceContacts) {
        if (!contact.isDuplicate) {
          contact.selected = selectAll;
        }
      }
    });
  }

  int get _selectedCount => _deviceContacts.where((c) => c.selected && !c.isDuplicate).length;
  int get _duplicateCount => _deviceContacts.where((c) => c.isDuplicate).length;

  Future<void> _importSelected() async {
    if (_selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('no_contacts_selected'))),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = _selectedCount;
    });

    // Always import to "imported_contacts" group
    const importGroupPath = 'imported_contacts';

    // Ensure the group exists with localized name in group.txt
    await _contactService.createGroup(
      importGroupPath,
      description: _i18n.t('imported_contacts_description'),
    );

    final result = await _importService.importContacts(
      contacts: _deviceContacts,
      collectionPath: widget.collectionPath,
      groupPath: importGroupPath,
      existingContacts: _existingContacts,
      onProgress: (imported, total) {
        setState(() {
          _importProgress = imported;
          _importTotal = total;
        });
      },
    );

    setState(() {
      _isImporting = false;
    });

    if (!mounted) return;

    // Show result dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('import_complete')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_i18n.t('import_summary', params: [
              result.importedCount.toString(),
              result.skippedDuplicates.toString(),
              result.failedCount.toString(),
            ])),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _i18n.t('errors'),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              ...result.errors.take(5).map((e) => Text(
                    '• $e',
                    style: const TextStyle(fontSize: 12),
                  )),
              if (result.errors.length > 5)
                Text(
                  '... and ${result.errors.length - 5} more',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('ok')),
          ),
        ],
      ),
    );

    // Return to contacts browser with refresh signal
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('import_contacts')),
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_i18n.t('fetching_contacts')),
          ],
        ),
      );
    }

    if (_isImporting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_i18n.t('import_progress', params: [
              _importProgress.toString(),
              _importTotal.toString(),
            ])),
          ],
        ),
      );
    }

    if (_permissionDenied) {
      return _buildPermissionDeniedView();
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    return _buildContactList();
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.contacts, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _permissionPermanentlyDenied
                  ? _i18n.t('contacts_permission_denied')
                  : _i18n.t('contacts_permission_required'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (_permissionPermanentlyDenied)
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: Text(_i18n.t('open_settings')),
                onPressed: () => openAppSettings(),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(_i18n.t('try_again')),
                onPressed: _checkPermissionAndLoad,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactList() {
    return Column(
      children: [
        // Select All / Deselect All buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => _toggleSelectAll(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: Text(_i18n.t('select_all')),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _toggleSelectAll(false),
                icon: const Icon(Icons.deselect, size: 18),
                label: Text(_i18n.t('deselect_all')),
              ),
            ],
          ),
        ),
        // Summary bar
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_deviceContacts.length} ${_i18n.t('contacts').toLowerCase()}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (_duplicateCount > 0)
                Chip(
                  label: Text('$_duplicateCount ${_i18n.t('duplicate_contact').toLowerCase()}'),
                  backgroundColor: Colors.orange.withAlpha(51),
                  labelStyle: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
        // Contact list
        Expanded(
          child: ListView.builder(
            itemCount: _deviceContacts.length,
            itemBuilder: (context, index) {
              final contact = _deviceContacts[index];
              return _buildContactTile(contact);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContactTile(DeviceContactInfo contact) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: contact.isDuplicate ? Colors.grey : Colors.blue,
        backgroundImage: contact.photo != null ? MemoryImage(contact.photo!) : null,
        child: contact.photo == null
            ? Text(
                contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      title: Text(
        contact.displayName,
        style: TextStyle(
          color: contact.isDuplicate ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        _buildSubtitle(contact),
        style: TextStyle(
          color: contact.isDuplicate ? Colors.grey : null,
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: contact.isDuplicate
          ? Chip(
              label: Text(_i18n.t('duplicate_contact')),
              backgroundColor: Colors.orange.withAlpha(51),
              labelStyle: const TextStyle(fontSize: 10),
            )
          : Checkbox(
              value: contact.selected,
              onChanged: (value) {
                setState(() {
                  contact.selected = value ?? false;
                });
              },
            ),
      onTap: contact.isDuplicate
          ? null
          : () {
              setState(() {
                contact.selected = !contact.selected;
              });
            },
    );
  }

  String _buildSubtitle(DeviceContactInfo contact) {
    final parts = <String>[];
    if (contact.phones.isNotEmpty) parts.add(contact.phones.first);
    if (contact.emails.isNotEmpty) parts.add(contact.emails.first);
    return parts.join(' • ');
  }

  Widget? _buildBottomBar() {
    if (_isLoading || _isImporting || _permissionDenied || _errorMessage != null) {
      return null;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.download),
          label: Text(_i18n.t('import_selected', params: [_selectedCount.toString()])),
          onPressed: _selectedCount > 0 ? _importSelected : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ),
    );
  }
}
