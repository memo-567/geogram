/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';
import 'package:flutter/material.dart';

import '../models/device_definition.dart';

/// Card widget for displaying a flashable device
class DeviceCard extends StatelessWidget {
  final DeviceDefinition device;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? language;

  const DeviceCard({
    super.key,
    required this.device,
    this.isSelected = false,
    this.onTap,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = language != null
        ? device.getDescription(language!)
        : device.description;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 180,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: _buildImage(),
            ),

            // Device info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    device.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 4),

                  // Chip info
                  Row(
                    children: [
                      Icon(
                        Icons.memory,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          device.chip,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Description
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // USB info
                  if (device.usb != null) _buildUsbInfo(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final photoPath = device.photoPath;

    if (photoPath != null) {
      final file = File(photoPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          height: 100,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 100,
      width: double.infinity,
      color: Colors.grey.shade200,
      child: Icon(
        _getDeviceIcon(),
        size: 48,
        color: Colors.grey.shade400,
      ),
    );
  }

  IconData _getDeviceIcon() {
    switch (device.family.toLowerCase()) {
      case 'esp32':
        return Icons.developer_board;
      case 'quansheng':
        return Icons.radio;
      case 'stm32':
        return Icons.memory;
      default:
        return Icons.devices_other;
    }
  }

  Widget _buildUsbInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.usb,
            size: 12,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(width: 4),
          Text(
            '${device.usb!.vid}:${device.usb!.pid}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact device chip for horizontal lists
class DeviceChip extends StatelessWidget {
  final DeviceDefinition device;
  final bool isSelected;
  final VoidCallback? onTap;

  const DeviceChip({
    super.key,
    required this.device,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(device.title),
      avatar: Icon(_getDeviceIcon(), size: 16),
      selected: isSelected,
      onSelected: (_) => onTap?.call(),
    );
  }

  IconData _getDeviceIcon() {
    switch (device.family.toLowerCase()) {
      case 'esp32':
        return Icons.developer_board;
      case 'quansheng':
        return Icons.radio;
      default:
        return Icons.devices_other;
    }
  }
}
