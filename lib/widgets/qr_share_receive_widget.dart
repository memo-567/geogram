/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/i18n_service.dart';

/// Configuration for a shareable field
class QrShareField {
  /// Unique identifier for this field
  final String id;

  /// Display label for the field
  final String label;

  /// Icon to display
  final IconData icon;

  /// Whether this field is required and cannot be deselected
  final bool isRequired;

  /// Whether this field is currently selected
  bool isSelected;

  /// Optional sub-fields (e.g., individual phone numbers)
  final List<QrShareSubField>? subFields;

  /// Estimated size in bytes
  final int estimatedSize;

  QrShareField({
    required this.id,
    required this.label,
    required this.icon,
    this.isRequired = false,
    this.isSelected = true,
    this.subFields,
    this.estimatedSize = 0,
  });
}

/// Sub-field for multi-value fields (e.g., individual phone numbers)
class QrShareSubField {
  /// Unique identifier
  final String id;

  /// Display value
  final String value;

  /// Whether this sub-field is selected
  bool isSelected;

  /// Parent field id
  final String parentId;

  QrShareSubField({
    required this.id,
    required this.value,
    required this.parentId,
    this.isSelected = true,
  });
}

/// Result of scanning a QR code
class QrScanResult<T> {
  final T? data;
  final String? error;

  QrScanResult({this.data, this.error});

  bool get isSuccess => data != null && error == null;
}

/// Configuration for the QR share/receive widget
class QrShareReceiveConfig<T> {
  /// Title for the share tab
  final String shareTabTitle;

  /// Title for the receive tab
  final String receiveTabTitle;

  /// App bar title
  final String appBarTitle;

  /// Function to get available fields from data
  final List<QrShareField> Function(T data) getFields;

  /// Function to encode data with selected fields to JSON string
  final String Function(T data, List<QrShareField> selectedFields) encode;

  /// Function to decode JSON string back to data
  final QrScanResult<T> Function(String json) decode;

  /// Function to validate decoded data before saving
  final Future<String?> Function(T data)? validate;

  /// Function to save/handle scanned data
  final Future<bool> Function(T data) onSave;

  /// Function to build preview widget for scanned data
  final Widget Function(BuildContext context, T data) buildPreview;

  /// QR code format version identifier
  final String formatVersion;

  /// Maximum recommended QR size in bytes
  final int maxRecommendedSize;

  /// Warning threshold in bytes
  final int warningThreshold;

  QrShareReceiveConfig({
    required this.shareTabTitle,
    required this.receiveTabTitle,
    required this.appBarTitle,
    required this.getFields,
    required this.encode,
    required this.decode,
    required this.onSave,
    required this.buildPreview,
    this.validate,
    this.formatVersion = '1.0',
    this.maxRecommendedSize = 1500,
    this.warningThreshold = 1000,
  });
}

/// Size status for QR code
enum QrSizeStatus { ok, warning, tooLarge }

/// Reusable QR code share and receive widget with tabs
///
/// This widget provides a two-tab interface for:
/// - **Send tab**: Display QR code with selectable fields
/// - **Receive tab**: Camera-based QR code scanner
///
/// It's designed to be reusable across different data types (contacts, profiles, etc.)
/// by providing configuration through [QrShareReceiveConfig].
class QrShareReceiveWidget<T> extends StatefulWidget {
  /// The data to share (for send tab)
  final T? dataToShare;

  /// Configuration for the widget
  final QrShareReceiveConfig<T> config;

  /// Localization service
  final I18nService i18n;

  /// Initial tab index (0 = Send, 1 = Receive)
  final int initialTab;

  /// Callback when data is successfully received
  final void Function(T data)? onDataReceived;

  const QrShareReceiveWidget({
    super.key,
    this.dataToShare,
    required this.config,
    required this.i18n,
    this.initialTab = 0,
    this.onDataReceived,
  });

  @override
  State<QrShareReceiveWidget<T>> createState() => _QrShareReceiveWidgetState<T>();
}

class _QrShareReceiveWidgetState<T> extends State<QrShareReceiveWidget<T>>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<QrShareField> _fields = [];
  String _qrData = '';
  int _qrSize = 0;
  QrSizeStatus _sizeStatus = QrSizeStatus.ok;

  // Scanner state
  MobileScannerController? _scannerController;
  bool _isScanning = false;
  bool _hasScanned = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(_onTabChanged);

    if (widget.dataToShare != null) {
      _initializeFields();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_isScanning && !_permissionDenied) {
      _startScanner();
    } else if (_tabController.index == 0) {
      _stopScanner();
    }
  }

  void _initializeFields() {
    _fields = widget.config.getFields(widget.dataToShare as T);
    _updateQrData();
  }

  void _updateQrData() {
    if (widget.dataToShare == null) return;

    _qrData = widget.config.encode(widget.dataToShare as T, _fields);
    _qrSize = utf8.encode(_qrData).length;
    _sizeStatus = _getSizeStatus(_qrSize);
    setState(() {});
  }

  QrSizeStatus _getSizeStatus(int bytes) {
    if (bytes > widget.config.maxRecommendedSize) {
      return QrSizeStatus.tooLarge;
    } else if (bytes > widget.config.warningThreshold) {
      return QrSizeStatus.warning;
    }
    return QrSizeStatus.ok;
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

  void _toggleField(QrShareField field) {
    if (field.isRequired) return;
    setState(() {
      field.isSelected = !field.isSelected;
      // If field has subfields, toggle all of them
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
      // Update parent field selection based on any selected subfields
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

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.i18n.t('copied_to_clipboard', params: ['JSON'])),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Scanner methods
  Future<void> _startScanner() async {
    // mobile_scanner supports: Android, iOS, macOS, Web
    // Only Windows and Linux desktop don't have camera support
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
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
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() {
      _isScanning = true;
      _hasScanned = false;
      _scanError = null;
    });
  }

  void _stopScanner() {
    _scannerController?.stop();
    setState(() {
      _isScanning = false;
    });
  }

  void _resetScanner() {
    setState(() {
      _hasScanned = false;
      _scanError = null;
    });
    _scannerController?.start();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;

      final result = widget.config.decode(value);
      if (result.isSuccess) {
        setState(() {
          _hasScanned = true;
        });
        _scannerController?.stop();
        _handleScannedData(result.data as T);
        return;
      }
    }
  }

  Future<void> _handleScannedData(T data) async {
    // Validate if validator is provided
    if (widget.config.validate != null) {
      final error = await widget.config.validate!(data);
      if (error != null) {
        _showError(error);
        _resetScanner();
        return;
      }
    }

    // Show preview and confirm
    final shouldSave = await _showPreviewDialog(data);
    if (shouldSave == true) {
      final success = await widget.config.onSave(data);
      if (success) {
        widget.onDataReceived?.call(data);
        if (mounted) {
          _showSuccess(widget.i18n.t('saved_successfully'));
          Navigator.pop(context, true);
        }
      } else {
        _showError(widget.i18n.t('save_failed'));
        _resetScanner();
      }
    } else {
      _resetScanner();
    }
  }

  Future<bool?> _showPreviewDialog(T data) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(widget.i18n.t('data_scanned')),
          ],
        ),
        content: SingleChildScrollView(
          child: widget.config.buildPreview(context, data),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.appBarTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.qr_code),
              text: widget.config.shareTabTitle,
            ),
            Tab(
              icon: const Icon(Icons.qr_code_scanner),
              text: widget.config.receiveTabTitle,
            ),
          ],
        ),
        actions: [
          if (_tabController.index == 0 && widget.dataToShare != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyToClipboard,
              tooltip: widget.i18n.t('copy_to_clipboard', params: ['JSON']),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSendTab(),
          _buildReceiveTab(),
        ],
      ),
    );
  }

  Widget _buildSendTab() {
    if (widget.dataToShare == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                widget.i18n.t('no_data_to_share'),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        children: [
          // QR Code Display
          Container(
            padding: const EdgeInsets.all(24),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getSizeColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getSizeColor().withValues(alpha: 0.5)),
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
        ],
      ),
    );
  }

  Widget _buildFieldTile(QrShareField field) {
    final theme = Theme.of(context);
    final hasSubFields = field.subFields != null && field.subFields!.isNotEmpty;

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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
        // Camera preview
        MobileScanner(
          controller: _scannerController!,
          onDetect: _onDetect,
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
