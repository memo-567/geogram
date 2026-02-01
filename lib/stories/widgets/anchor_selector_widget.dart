/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/element_position.dart';

/// A 9-point grid widget for selecting anchor points visually
class AnchorSelectorWidget extends StatelessWidget {
  final AnchorPoint selected;
  final ValueChanged<AnchorPoint> onChanged;
  final double size;

  const AnchorSelectorWidget({
    super.key,
    required this.selected,
    required this.onChanged,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotSize = size / 5;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          // Grid lines
          CustomPaint(
            size: Size(size, size),
            painter: _GridLinesPainter(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          // Anchor points
          for (final anchor in AnchorPoint.values)
            _buildAnchorDot(anchor, dotSize, theme),
        ],
      ),
    );
  }

  Widget _buildAnchorDot(AnchorPoint anchor, double dotSize, ThemeData theme) {
    final isSelected = anchor == selected;
    final (x, y) = _getAnchorPosition(anchor);

    return Positioned(
      left: x * size - dotSize / 2,
      top: y * size - dotSize / 2,
      child: GestureDetector(
        onTap: () => onChanged(anchor),
        child: Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: dotSize * 0.4,
                    height: dotSize * 0.4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  (double, double) _getAnchorPosition(AnchorPoint anchor) {
    switch (anchor) {
      case AnchorPoint.topLeft:
        return (0.15, 0.15);
      case AnchorPoint.topCenter:
        return (0.5, 0.15);
      case AnchorPoint.topRight:
        return (0.85, 0.15);
      case AnchorPoint.centerLeft:
        return (0.15, 0.5);
      case AnchorPoint.center:
        return (0.5, 0.5);
      case AnchorPoint.centerRight:
        return (0.85, 0.5);
      case AnchorPoint.bottomLeft:
        return (0.15, 0.85);
      case AnchorPoint.bottomCenter:
        return (0.5, 0.85);
      case AnchorPoint.bottomRight:
        return (0.85, 0.85);
    }
  }
}

class _GridLinesPainter extends CustomPainter {
  final Color color;

  _GridLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    // Vertical lines
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.1),
      Offset(size.width * 0.5, size.height * 0.9),
      paint,
    );

    // Horizontal lines
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.5),
      Offset(size.width * 0.9, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridLinesPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

/// Compact anchor selector for inline use
class CompactAnchorSelector extends StatelessWidget {
  final AnchorPoint selected;
  final ValueChanged<AnchorPoint> onChanged;

  const CompactAnchorSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AnchorPoint>(
      initialValue: selected,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final anchor in AnchorPoint.values)
          PopupMenuItem(
            value: anchor,
            child: Row(
              children: [
                Icon(
                  _getIconForAnchor(anchor),
                  size: 18,
                  color: anchor == selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 8),
                Text(_getLabelForAnchor(anchor)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getIconForAnchor(selected), size: 18),
            const SizedBox(width: 8),
            Text(_getLabelForAnchor(selected)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  IconData _getIconForAnchor(AnchorPoint anchor) {
    switch (anchor) {
      case AnchorPoint.topLeft:
        return Icons.north_west;
      case AnchorPoint.topCenter:
        return Icons.north;
      case AnchorPoint.topRight:
        return Icons.north_east;
      case AnchorPoint.centerLeft:
        return Icons.west;
      case AnchorPoint.center:
        return Icons.center_focus_strong;
      case AnchorPoint.centerRight:
        return Icons.east;
      case AnchorPoint.bottomLeft:
        return Icons.south_west;
      case AnchorPoint.bottomCenter:
        return Icons.south;
      case AnchorPoint.bottomRight:
        return Icons.south_east;
    }
  }

  String _getLabelForAnchor(AnchorPoint anchor) {
    switch (anchor) {
      case AnchorPoint.topLeft:
        return 'Top Left';
      case AnchorPoint.topCenter:
        return 'Top Center';
      case AnchorPoint.topRight:
        return 'Top Right';
      case AnchorPoint.centerLeft:
        return 'Center Left';
      case AnchorPoint.center:
        return 'Center';
      case AnchorPoint.centerRight:
        return 'Center Right';
      case AnchorPoint.bottomLeft:
        return 'Bottom Left';
      case AnchorPoint.bottomCenter:
        return 'Bottom Center';
      case AnchorPoint.bottomRight:
        return 'Bottom Right';
    }
  }
}
