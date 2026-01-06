/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../services/contact_service.dart';
import '../services/i18n_service.dart';

/// Contact Merge page - find and merge duplicate contacts
class ContactMergePage extends StatefulWidget {
  final ContactService contactService;
  final I18nService i18n;
  final List<Contact>? contactsToMerge; // For manual selection mode

  const ContactMergePage({
    super.key,
    required this.contactService,
    required this.i18n,
    this.contactsToMerge,
  });

  @override
  State<ContactMergePage> createState() => _ContactMergePageState();
}

class _ContactMergePageState extends State<ContactMergePage> {
  List<DuplicateGroup> _duplicateGroups = [];
  bool _isLoading = true;
  bool _isManualMode = false;

  @override
  void initState() {
    super.initState();
    _isManualMode = widget.contactsToMerge != null && widget.contactsToMerge!.isNotEmpty;
    if (_isManualMode) {
      // Manual mode - show the merge dialog for selected contacts
      _duplicateGroups = [
        DuplicateGroup(
          contacts: widget.contactsToMerge!,
          matchReason: widget.i18n.t('manual_selection'),
        ),
      ];
      _isLoading = false;
    } else {
      // Auto-detect mode
      _findDuplicates();
    }
  }

  Future<void> _findDuplicates() async {
    setState(() => _isLoading = true);

    final allContacts = <Contact>[];
    await for (final contact in widget.contactService.loadAllContactsStream()) {
      allContacts.add(contact);
    }

    final groups = <DuplicateGroup>[];
    final processed = <String>{};

    for (var i = 0; i < allContacts.length; i++) {
      if (processed.contains(allContacts[i].callsign)) continue;

      final duplicates = <Contact>[allContacts[i]];
      String? matchReason;

      for (var j = i + 1; j < allContacts.length; j++) {
        if (processed.contains(allContacts[j].callsign)) continue;

        final reason = _checkDuplicate(allContacts[i], allContacts[j]);
        if (reason != null) {
          duplicates.add(allContacts[j]);
          matchReason ??= reason;
        }
      }

      if (duplicates.length > 1) {
        groups.add(DuplicateGroup(
          contacts: duplicates,
          matchReason: matchReason ?? widget.i18n.t('unknown_match'),
        ));
        for (var dup in duplicates) {
          processed.add(dup.callsign);
        }
      }
    }

    setState(() {
      _duplicateGroups = groups;
      _isLoading = false;
    });
  }

  String? _checkDuplicate(Contact a, Contact b) {
    // Check exact name match (case-insensitive)
    if (a.displayName.toLowerCase().trim() == b.displayName.toLowerCase().trim() &&
        a.displayName.isNotEmpty) {
      return widget.i18n.t('match_by_name');
    }

    // Check phone number match (normalized)
    for (final phoneA in a.phones) {
      for (final phoneB in b.phones) {
        if (_normalizePhone(phoneA) == _normalizePhone(phoneB)) {
          return widget.i18n.t('match_by_phone');
        }
      }
    }

    // Check similar name (first 5 chars match, min 5 chars)
    final nameA = a.displayName.toLowerCase().trim();
    final nameB = b.displayName.toLowerCase().trim();
    if (nameA.length >= 5 && nameB.length >= 5 &&
        nameA.substring(0, 5) == nameB.substring(0, 5)) {
      return widget.i18n.t('match_by_similar_name');
    }

    return null;
  }

  String _normalizePhone(String phone) {
    // Remove spaces, dashes, parentheses, and common prefixes
    return phone
        .replaceAll(RegExp(r'[\s\-\(\)\+]'), '')
        .replaceAll(RegExp(r'^00'), '')
        .replaceAll(RegExp(r'^0'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('merge_contacts')),
        actions: [
          if (!_isManualMode && !_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _findDuplicates,
              tooltip: widget.i18n.t('refresh'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _duplicateGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.i18n.t('no_duplicates_found'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.i18n.t('all_contacts_unique'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _duplicateGroups.length,
                  itemBuilder: (context, index) {
                    return _buildDuplicateGroupCard(_duplicateGroups[index], index);
                  },
                ),
    );
  }

  Widget _buildDuplicateGroupCard(DuplicateGroup group, int index) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with match reason
            Row(
              children: [
                Icon(Icons.people, color: Colors.orange.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.i18n.t('potential_duplicates'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Chip(
                  label: Text(
                    group.matchReason,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: Colors.orange.shade100,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Contact list
            ...group.contacts.map((contact) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue,
                    child: Text(
                      _getInitials(contact.displayName),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  title: Text(contact.displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.callsign,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      if (contact.phones.isNotEmpty)
                        Text(
                          contact.phones.first,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  isThreeLine: contact.phones.isNotEmpty,
                )),
            const SizedBox(height: 8),
            // Merge button
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _showMergeDialog(group),
                icon: const Icon(Icons.merge, size: 18),
                label: Text(widget.i18n.t('merge')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _showMergeDialog(DuplicateGroup group) async {
    Contact? primaryContact = group.contacts.first;

    final result = await showDialog<Contact>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.i18n.t('select_primary_contact')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.i18n.t('primary_contact_kept'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 12),
                ...group.contacts.map((contact) => RadioListTile<Contact>(
                      value: contact,
                      groupValue: primaryContact,
                      onChanged: (value) {
                        setDialogState(() => primaryContact = value);
                      },
                      title: Text(contact.displayName),
                      subtitle: Text(contact.callsign),
                      dense: true,
                    )),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  widget.i18n.t('merge_preview'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                _buildMergePreview(group, primaryContact!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.i18n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, primaryContact),
              child: Text(widget.i18n.t('merge')),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      await _performMerge(group, result);
    }
  }

  Widget _buildMergePreview(DuplicateGroup group, Contact primary) {
    // Combine all data from all contacts
    final allPhones = <String>{};
    final allEmails = <String>{};
    final allTags = <String>{};

    for (final contact in group.contacts) {
      allPhones.addAll(contact.phones);
      allEmails.addAll(contact.emails);
      allTags.addAll(contact.tags);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.i18n.t('field_display_name')}: ${primary.displayName}'),
          Text('${widget.i18n.t('field_callsign')}: ${primary.callsign}'),
          if (allPhones.isNotEmpty)
            Text('${widget.i18n.t('field_phones')}: ${allPhones.length}'),
          if (allEmails.isNotEmpty)
            Text('${widget.i18n.t('field_emails')}: ${allEmails.length}'),
          if (allTags.isNotEmpty)
            Text('${widget.i18n.t('field_tags')}: ${allTags.join(', ')}'),
        ],
      ),
    );
  }

  Future<void> _performMerge(DuplicateGroup group, Contact primary) async {
    // Collect all data from secondary contacts
    final allPhones = <String>{...primary.phones};
    final allEmails = <String>{...primary.emails};
    final allAddresses = <String>{...primary.addresses};
    final allWebsites = <String>{...primary.websites};
    final allTags = <String>{...primary.tags};
    final allRadioCallsigns = <String>{...primary.radioCallsigns};
    final allSocialHandles = Map<String, String>.from(primary.socialHandles);
    final allHistoryEntries = List<ContactHistoryEntry>.from(primary.historyEntries);

    for (final contact in group.contacts) {
      if (contact.callsign == primary.callsign) continue;

      allPhones.addAll(contact.phones);
      allEmails.addAll(contact.emails);
      allAddresses.addAll(contact.addresses);
      allWebsites.addAll(contact.websites);
      allTags.addAll(contact.tags);
      allRadioCallsigns.addAll(contact.radioCallsigns);
      allSocialHandles.addAll(contact.socialHandles);
      allHistoryEntries.addAll(contact.historyEntries);
    }

    // Sort history by date
    allHistoryEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Create merged contact
    final mergedContact = Contact(
      displayName: primary.displayName,
      callsign: primary.callsign,
      created: primary.created,
      firstSeen: primary.firstSeen,
      npub: primary.npub,
      notes: primary.notes.isNotEmpty
          ? primary.notes
          : group.contacts.firstWhere((c) => c.notes.isNotEmpty, orElse: () => primary).notes,
      phones: allPhones.toList(),
      emails: allEmails.toList(),
      addresses: allAddresses.toList(),
      websites: allWebsites.toList(),
      tags: allTags.toList(),
      radioCallsigns: allRadioCallsigns.toList(),
      socialHandles: allSocialHandles,
      historyEntries: allHistoryEntries,
      locations: primary.locations,
    );

    // Save merged contact
    final error = await widget.contactService.saveContact(
      mergedContact,
      groupPath: primary.groupPath,
    );

    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Delete secondary contacts
    for (final contact in group.contacts) {
      if (contact.callsign == primary.callsign) continue;
      if (contact.filePath != null) {
        await widget.contactService.deleteContact(contact.callsign, groupPath: contact.groupPath);
      }
    }

    // Remove this group from the list
    setState(() {
      _duplicateGroups.remove(group);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.i18n.t('contacts_merged_successfully')),
          backgroundColor: Colors.green,
        ),
      );

      // If in manual mode or no more duplicates, pop back
      if (_isManualMode || _duplicateGroups.isEmpty) {
        Navigator.pop(context, true);
      }
    }
  }
}

/// Represents a group of potentially duplicate contacts
class DuplicateGroup {
  final List<Contact> contacts;
  final String matchReason;

  DuplicateGroup({
    required this.contacts,
    required this.matchReason,
  });
}
