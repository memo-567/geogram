/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/contact.dart';
import '../services/contact_qr_service.dart';
import '../services/i18n_service.dart';

/// Page for sharing a contact via QR code with field selection
class ContactQrSharePage extends StatefulWidget {
  final Contact contact;
  final I18nService i18n;

  const ContactQrSharePage({
    super.key,
    required this.contact,
    required this.i18n,
  });

  @override
  State<ContactQrSharePage> createState() => _ContactQrSharePageState();
}

class _ContactQrSharePageState extends State<ContactQrSharePage> {
  final ContactQrService _qrService = ContactQrService();
  late Set<ContactQrField> _selectedFields;
  late List<ContactQrFieldInfo> _availableFields;
  late String _qrData;
  late int _qrSize;
  late QrSizeStatus _sizeStatus;

  @override
  void initState() {
    super.initState();
    _availableFields = _qrService.getAvailableFields(widget.contact);

    // Default: select all available fields
    _selectedFields = _availableFields.map((f) => f.field).toSet();

    _updateQrData();
  }

  void _updateQrData() {
    _qrData = _qrService.encodeContact(widget.contact, _selectedFields);
    _qrSize = _qrService.calculateSize(_qrData);
    _sizeStatus = _qrService.checkSizeStatus(_qrSize);
  }

  void _toggleField(ContactQrField field) {
    setState(() {
      if (_selectedFields.contains(field)) {
        _selectedFields.remove(field);
      } else {
        _selectedFields.add(field);
      }
      _updateQrData();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedFields = _availableFields.map((f) => f.field).toSet();
      _updateQrData();
    });
  }

  void _selectMinimal() {
    setState(() {
      _selectedFields = {...ContactQrService.requiredFields};
      // Also include npub if available
      if (_availableFields.any((f) => f.field == ContactQrField.npub)) {
        _selectedFields.add(ContactQrField.npub);
      }
      _updateQrData();
    });
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

  String _getFieldLabel(ContactQrField field) {
    switch (field) {
      case ContactQrField.displayName:
        return widget.i18n.t('field_display_name');
      case ContactQrField.callsign:
        return widget.i18n.t('field_callsign');
      case ContactQrField.npub:
        return widget.i18n.t('field_npub');
      case ContactQrField.emails:
        return widget.i18n.t('field_emails');
      case ContactQrField.phones:
        return widget.i18n.t('field_phones');
      case ContactQrField.addresses:
        return widget.i18n.t('field_addresses');
      case ContactQrField.websites:
        return widget.i18n.t('field_websites');
      case ContactQrField.locations:
        return widget.i18n.t('field_locations');
      case ContactQrField.socialHandles:
        return widget.i18n.t('field_social_handles');
      case ContactQrField.tags:
        return widget.i18n.t('field_tags');
      case ContactQrField.radioCallsigns:
        return widget.i18n.t('field_radio_callsigns');
      case ContactQrField.notes:
        return widget.i18n.t('field_notes');
    }
  }

  IconData _getFieldIcon(ContactQrField field) {
    switch (field) {
      case ContactQrField.displayName:
        return Icons.person;
      case ContactQrField.callsign:
        return Icons.tag;
      case ContactQrField.npub:
        return Icons.key;
      case ContactQrField.emails:
        return Icons.email;
      case ContactQrField.phones:
        return Icons.phone;
      case ContactQrField.addresses:
        return Icons.location_on;
      case ContactQrField.websites:
        return Icons.language;
      case ContactQrField.locations:
        return Icons.place;
      case ContactQrField.socialHandles:
        return Icons.share;
      case ContactQrField.tags:
        return Icons.label;
      case ContactQrField.radioCallsigns:
        return Icons.radio;
      case ContactQrField.notes:
        return Icons.note;
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.i18n.t('copied_to_clipboard', params: ['JSON'])),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('share_contact')),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyToClipboard,
            tooltip: widget.i18n.t('copy_to_clipboard', params: ['JSON']),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // QR Code Display
            Container(
              padding: const EdgeInsets.all(24),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: Column(
                children: [
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
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

                  // Contact name
                  Text(
                    widget.contact.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.contact.callsign,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Size indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getSizeColor().withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getSizeColor().withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getSizeIcon(),
                          size: 18,
                          color: _getSizeColor(),
                        ),
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
              itemCount: _availableFields.length,
              itemBuilder: (context, index) {
                final fieldInfo = _availableFields[index];
                final isSelected = _selectedFields.contains(fieldInfo.field);

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: fieldInfo.isRequired
                      ? null // Disable toggle for required fields
                      : (value) => _toggleField(fieldInfo.field),
                  title: Row(
                    children: [
                      Icon(
                        _getFieldIcon(fieldInfo.field),
                        size: 20,
                        color: fieldInfo.isRequired
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getFieldLabel(fieldInfo.field),
                          style: TextStyle(
                            fontWeight: fieldInfo.isRequired ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      if (fieldInfo.count > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            fieldInfo.count.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: fieldInfo.isRequired
                      ? Text(
                          widget.i18n.t('field_required'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Text(
                          '~${fieldInfo.estimatedSize} bytes',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  secondary: fieldInfo.isRequired
                      ? Icon(
                          Icons.lock,
                          size: 18,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
