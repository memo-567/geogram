/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contact.dart';
import '../services/contact_qr_service.dart';
import '../services/contact_service.dart';
import '../services/i18n_service.dart';

/// Page for scanning contact QR codes
class ContactQrScanPage extends StatefulWidget {
  final ContactService contactService;
  final I18nService i18n;

  const ContactQrScanPage({
    super.key,
    required this.contactService,
    required this.i18n,
  });

  @override
  State<ContactQrScanPage> createState() => _ContactQrScanPageState();
}

class _ContactQrScanPageState extends State<ContactQrScanPage> {
  final ContactQrService _qrService = ContactQrService();
  bool _isLoading = true;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  bool _hasScanned = false;
  String? _errorMessage;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _checkPlatformAndPermission();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _checkPlatformAndPermission() async {
    // flutter_zxing supports: Android, iOS, macOS
    // Web and Linux/Windows desktop don't have camera support via ZXing
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      setState(() {
        _isLoading = false;
        _errorMessage = widget.i18n.t('camera_not_supported');
      });
      return;
    }

    await _checkPermissionAndStart();
  }

  Future<void> _checkPermissionAndStart() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _permissionPermanentlyDenied = false;
      _errorMessage = null;
    });

    // Check camera permission
    final status = await Permission.camera.status;

    if (status.isGranted) {
      _startScanner();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
        _permissionPermanentlyDenied = true;
      });
    } else {
      // Request permission
      final result = await Permission.camera.request();

      if (result.isGranted) {
        _startScanner();
      } else {
        setState(() {
          _isLoading = false;
          _permissionDenied = true;
          _permissionPermanentlyDenied = result.isPermanentlyDenied;
        });
      }
    }
  }

  void _startScanner() {
    setState(() {
      _isLoading = false;
    });
  }

  void _onScan(Code code) {
    if (_hasScanned) return; // Prevent multiple scans
    if (!code.isValid) return;

    final value = code.text;
    if (value == null) return;

    // Try to parse as Geogram contact
    if (_qrService.isValidGeogramContact(value)) {
      _hasScanned = true;
      _handleScannedContact(value);
    }
  }

  Future<void> _handleScannedContact(String jsonData) async {
    final contact = _qrService.decodeContact(jsonData);

    if (contact == null) {
      _showError(widget.i18n.t('invalid_qr_code'));
      _resetScanner();
      return;
    }

    // Show confirmation dialog
    final result = await _showContactPreview(contact);

    if (result == true) {
      await _saveContact(contact);
    } else {
      _resetScanner();
    }
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
    });
  }

  Future<bool?> _showContactPreview(Contact contact) {
    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.person_add,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(widget.i18n.t('contact_scanned')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Contact name
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  contact.callsign,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),

              const Divider(),

              // Fields included
              if (contact.npub != null) _buildFieldRow(Icons.key, 'NPUB', contact.npub!.substring(0, 16) + '...'),
              if (contact.emails.isNotEmpty) _buildFieldRow(Icons.email, widget.i18n.t('field_emails'), '${contact.emails.length}'),
              if (contact.phones.isNotEmpty) _buildFieldRow(Icons.phone, widget.i18n.t('field_phones'), '${contact.phones.length}'),
              if (contact.addresses.isNotEmpty) _buildFieldRow(Icons.location_on, widget.i18n.t('field_addresses'), '${contact.addresses.length}'),
              if (contact.websites.isNotEmpty) _buildFieldRow(Icons.language, widget.i18n.t('field_websites'), '${contact.websites.length}'),
              if (contact.tags.isNotEmpty) _buildFieldRow(Icons.label, widget.i18n.t('field_tags'), contact.tags.join(', ')),
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
            label: Text(widget.i18n.t('save_contact')),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveContact(Contact contact) async {
    try {
      // Check for duplicate
      final existing = await widget.contactService.getContactByCallsign(contact.callsign);

      if (existing != null) {
        // Show duplicate dialog
        final action = await _showDuplicateDialog(existing, contact);

        if (action == 'update') {
          // Update existing contact with new data
          final updated = existing.copyWith(
            displayName: contact.displayName,
            npub: contact.npub ?? existing.npub,
            emails: contact.emails.isNotEmpty ? contact.emails : existing.emails,
            phones: contact.phones.isNotEmpty ? contact.phones : existing.phones,
            addresses: contact.addresses.isNotEmpty ? contact.addresses : existing.addresses,
            websites: contact.websites.isNotEmpty ? contact.websites : existing.websites,
            locations: contact.locations.isNotEmpty ? contact.locations : existing.locations,
            socialHandles: contact.socialHandles.isNotEmpty ? contact.socialHandles : existing.socialHandles,
            tags: {...existing.tags, ...contact.tags}.toList(),
            radioCallsigns: contact.radioCallsigns.isNotEmpty ? contact.radioCallsigns : existing.radioCallsigns,
          );
          await widget.contactService.saveContact(updated);
          _showSuccess(widget.i18n.t('contact_updated'));
        } else if (action == 'new') {
          // Generate new callsign and save
          final newCallsign = await widget.contactService.generateUniqueCallsign(contact.displayName);
          final newContact = contact.copyWith(callsign: newCallsign);
          await widget.contactService.saveContact(newContact);
          _showSuccess(widget.i18n.t('contact_saved'));
        } else {
          // Cancelled
          _resetScanner();
          return;
        }
      } else {
        // Save new contact
        await widget.contactService.saveContact(contact);
        _showSuccess(widget.i18n.t('contact_saved'));
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError(e.toString());
      _resetScanner();
    }
  }

  Future<String?> _showDuplicateDialog(Contact existing, Contact scanned) {
    final theme = Theme.of(context);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.i18n.t('contact_already_exists')),
            ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('scan_contact')),
        actions: [
          if (!_isLoading && !_permissionDenied && _errorMessage == null)
            IconButton(
              icon: Icon(_flashOn ? Icons.flash_off : Icons.flash_on),
              onPressed: () {
                setState(() {
                  _flashOn = !_flashOn;
                });
              },
              tooltip: 'Toggle flash',
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorView(theme);
    }

    if (_permissionDenied) {
      return _buildPermissionDeniedView(theme);
    }

    return _buildScannerView(theme);
  }

  Widget _buildErrorView(ThemeData theme) {
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
              _errorMessage!,
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
                onPressed: _checkPermissionAndStart,
                icon: const Icon(Icons.refresh),
                label: Text(widget.i18n.t('try_again')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerView(ThemeData theme) {
    return Stack(
      children: [
        // Camera preview with ZXing scanner
        ReaderWidget(
          onScan: _onScan,
          isMultiScan: false,
          showFlashlight: false,  // We handle flash in AppBar
          showToggleCamera: false,
          showGallery: false,
          tryHarder: true,
          tryInverted: true,
        ),

        // Custom overlay
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
          ),
          child: Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
              ),
            ),
          ),
        ),

        // Clear the overlay inside the scanning frame
        Center(
          child: Container(
            width: 274,
            height: 274,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: Colors.transparent,
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
              color: theme.colorScheme.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  color: theme.colorScheme.primary,
                ),
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

    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(cornerLength, size.height),
      paint,
    );

    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
