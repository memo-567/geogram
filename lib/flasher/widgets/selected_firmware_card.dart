/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/material.dart';

import '../models/device_definition.dart';

/// Card showing the selected firmware for flashing
class SelectedFirmwareCard extends StatelessWidget {
  /// Selected device
  final DeviceDefinition? device;

  /// Selected version (null = use latest from URL)
  final FirmwareVersion? version;

  /// Callback to change selection
  final VoidCallback? onChangeTap;

  const SelectedFirmwareCard({
    super.key,
    this.device,
    this.version,
    this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (device == null) {
      return _buildEmptyCard(context, theme);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImage(context),
            ),
            const SizedBox(width: 16),

            // Device info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    device!.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Path: project / architecture / version
                  Text(
                    _buildPath(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Flash info
                  _buildFlashInfo(context, theme),
                ],
              ),
            ),

            // Change button
            if (onChangeTap != null)
              TextButton(
                onPressed: onChangeTap,
                child: const Text('Change'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, ThemeData theme) {
    return Card(
      child: InkWell(
        onTap: onChangeTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Text(
                'Select firmware from Library',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final photoPath = device!.photoPath;

    if (photoPath != null) {
      final file = File(photoPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          height: 80,
          width: 80,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholder(context),
        );
      }
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 80,
      width: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getDeviceIcon(),
        size: 40,
        color: theme.colorScheme.outline,
      ),
    );
  }

  IconData _getDeviceIcon() {
    if (device == null) return Icons.devices_other;

    switch (device!.effectiveArchitecture.toLowerCase()) {
      case 'esp32':
        return Icons.developer_board;
      case 'quansheng':
      case 'uv-k5':
        return Icons.radio;
      case 'stm32':
        return Icons.memory;
      default:
        return Icons.devices_other;
    }
  }

  String _buildPath() {
    if (device == null) return '';

    final parts = <String>[
      device!.effectiveProject,
      device!.effectiveArchitecture,
    ];

    if (version != null) {
      parts.add('v${version!.version}');
    } else if (device!.flash.firmwareUrl != null) {
      parts.add('latest');
    }

    return parts.join(' / ');
  }

  Widget _buildFlashInfo(BuildContext context, ThemeData theme) {
    final flash = device!.flash;
    final infoParts = <String>[];

    if (flash.flashSize != null) {
      infoParts.add(flash.flashSize!);
    }

    infoParts.add('${flash.protocol} protocol');

    if (version?.size != null) {
      infoParts.add(_formatSize(version!.size!));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: infoParts.map((info) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            info,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Compact inline display of selected firmware
class SelectedFirmwareChip extends StatelessWidget {
  final DeviceDefinition device;
  final FirmwareVersion? version;
  final VoidCallback? onTap;

  const SelectedFirmwareChip({
    super.key,
    required this.device,
    this.version,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ActionChip(
      avatar: Icon(
        _getDeviceIcon(),
        size: 16,
      ),
      label: Text(
        '${device.title}${version != null ? ' v${version!.version}' : ''}',
      ),
      onPressed: onTap,
      backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
    );
  }

  IconData _getDeviceIcon() {
    switch (device.effectiveArchitecture.toLowerCase()) {
      case 'esp32':
        return Icons.developer_board;
      case 'quansheng':
      case 'uv-k5':
        return Icons.radio;
      default:
        return Icons.devices_other;
    }
  }
}
