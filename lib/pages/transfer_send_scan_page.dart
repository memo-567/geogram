/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

import 'transfer_send_page.dart';

/// Page for scanning recipient QR codes for file transfer
class TransferSendScanPage extends StatefulWidget {
  const TransferSendScanPage({super.key});

  @override
  State<TransferSendScanPage> createState() => _TransferSendScanPageState();
}

class _TransferSendScanPageState extends State<TransferSendScanPage> {
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

  Future<void> _checkPlatformAndPermission() async {
    // flutter_zxing supports: Android, iOS, macOS
    // Web and Linux/Windows desktop don't have camera support via ZXing
    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Camera scanning is not supported on this platform. Please enter the callsign manually.';
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

    // Try to parse as Geogram transfer recipient
    if (_isValidGeogramTransfer(value)) {
      _hasScanned = true;
      _handleScannedRecipient(value);
    }
  }

  bool _isValidGeogramTransfer(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return json['geogram'] == '1.0' && json['callsign'] != null;
    } catch (_) {
      return false;
    }
  }

  void _handleScannedRecipient(String jsonData) {
    try {
      final json = jsonDecode(jsonData) as Map<String, dynamic>;
      final recipient = Recipient.fromQrJson(json);

      // Return the recipient to the calling page
      Navigator.pop(context, recipient);
    } catch (e) {
      _showError('Invalid QR code format');
      _resetScanner();
    }
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
    });
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
        title: const Text('Scan Recipient'),
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
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
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
                  ? 'Camera permission was denied. Please enable it in Settings to scan QR codes.'
                  : 'Camera permission is required to scan QR codes.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_permissionPermanentlyDenied)
              FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              )
            else
              FilledButton.icon(
                onPressed: _checkPermissionAndStart,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
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
          showFlashlight: false, // We handle flash in AppBar
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
                    'Scan recipient\'s QR code from their Receive page',
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
        ..quadraticBezierTo(
            size.width, size.height, size.width, size.height - radius)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
