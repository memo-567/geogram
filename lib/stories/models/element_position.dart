/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Anchor points for element positioning (9-point grid)
enum AnchorPoint {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Predefined sizes for elements
enum ElementSize {
  /// 20% of screen width
  small,

  /// 40% of screen width
  medium,

  /// 70% of screen width
  large,

  /// 100% of screen width
  full,

  /// Fit content naturally
  auto,
}

/// Anchor-based positioning system for story elements.
///
/// Instead of exact pixel or percentage coordinates, elements use an
/// anchor-based positioning system that adapts to any screen size.
class ElementPosition {
  /// Anchor point on the 9-point grid
  final AnchorPoint anchor;

  /// Horizontal offset from anchor (-50 to +50, percentage of screen)
  final double offsetX;

  /// Vertical offset from anchor (-50 to +50, percentage of screen)
  final double offsetY;

  /// Width: ElementSize or custom percentage (0-100)
  final dynamic width;

  /// Height: ElementSize or custom percentage (0-100), or 'auto'
  final dynamic height;

  const ElementPosition({
    this.anchor = AnchorPoint.center,
    this.offsetX = 0,
    this.offsetY = 0,
    this.width = ElementSize.medium,
    this.height = ElementSize.auto,
  });

  /// Get width as percentage (0-100)
  double get widthPercent {
    if (width is num) return (width as num).toDouble().clamp(0, 100);
    if (width is ElementSize) {
      switch (width as ElementSize) {
        case ElementSize.small:
          return 20;
        case ElementSize.medium:
          return 40;
        case ElementSize.large:
          return 70;
        case ElementSize.full:
          return 100;
        case ElementSize.auto:
          return 0; // Auto-sizing
      }
    }
    return 40; // Default to medium
  }

  /// Get height as percentage (0-100), or null for auto
  double? get heightPercent {
    if (height == ElementSize.auto) return null;
    if (height is num) return (height as num).toDouble().clamp(0, 100);
    if (height is ElementSize) {
      switch (height as ElementSize) {
        case ElementSize.small:
          return 10;
        case ElementSize.medium:
          return 20;
        case ElementSize.large:
          return 35;
        case ElementSize.full:
          return 100;
        case ElementSize.auto:
          return null;
      }
    }
    return null; // Auto-sizing
  }

  /// Get anchor point as percentage coordinates (0-100)
  /// Accounts for 5% safe zone padding
  (double x, double y) get anchorPercent {
    const safeZone = 5.0;
    const usable = 90.0; // 100 - 2 * safeZone

    switch (anchor) {
      case AnchorPoint.topLeft:
        return (safeZone, safeZone);
      case AnchorPoint.topCenter:
        return (50.0, safeZone);
      case AnchorPoint.topRight:
        return (safeZone + usable, safeZone);
      case AnchorPoint.centerLeft:
        return (safeZone, 50.0);
      case AnchorPoint.center:
        return (50.0, 50.0);
      case AnchorPoint.centerRight:
        return (safeZone + usable, 50.0);
      case AnchorPoint.bottomLeft:
        return (safeZone, safeZone + usable);
      case AnchorPoint.bottomCenter:
        return (50.0, safeZone + usable);
      case AnchorPoint.bottomRight:
        return (safeZone + usable, safeZone + usable);
    }
  }

  /// Calculate actual position on screen as percentages
  /// Returns (left, top) as percentages (0-100)
  (double left, double top) calculatePosition() {
    final (anchorX, anchorY) = anchorPercent;
    final width = widthPercent;

    // Adjust for element width (center the element on anchor)
    double left = anchorX + offsetX - (width / 2);
    double top = anchorY + offsetY;

    // Clamp to safe zones (ensure max >= min for wide elements)
    final maxLeft = (95 - width).clamp(0.0, 95.0);
    left = left.clamp(0.0, maxLeft);
    top = top.clamp(5.0, 95.0);

    return (left, top);
  }

  factory ElementPosition.fromJson(Map<String, dynamic> json) {
    return ElementPosition(
      anchor: _parseAnchor(json['anchor'] as String?),
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
      width: _parseSize(json['width']),
      height: _parseSize(json['height']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'anchor': anchor.name,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'width': _sizeToJson(width),
      'height': _sizeToJson(height),
    };
  }

  static AnchorPoint _parseAnchor(String? value) {
    if (value == null) return AnchorPoint.center;
    return AnchorPoint.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AnchorPoint.center,
    );
  }

  static dynamic _parseSize(dynamic value) {
    if (value == null) return ElementSize.auto;
    if (value is num) return value.toDouble();
    if (value is String) {
      return ElementSize.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ElementSize.auto,
      );
    }
    return ElementSize.auto;
  }

  static dynamic _sizeToJson(dynamic size) {
    if (size is ElementSize) return size.name;
    if (size is num) return size;
    return 'auto';
  }

  ElementPosition copyWith({
    AnchorPoint? anchor,
    double? offsetX,
    double? offsetY,
    dynamic width,
    dynamic height,
  }) {
    return ElementPosition(
      anchor: anchor ?? this.anchor,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
