/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Coupon status
enum CouponStatus {
  active,
  inactive,
  expired,
  depleted;

  static CouponStatus fromString(String value) {
    return CouponStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => CouponStatus.active,
    );
  }
}

/// Coupon discount type
enum CouponDiscountType {
  percentage,
  fixed,
  freeShipping;

  static CouponDiscountType fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    return CouponDiscountType.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => CouponDiscountType.fixed,
    );
  }

  String toFileString() {
    switch (this) {
      case CouponDiscountType.freeShipping:
        return 'free-shipping';
      default:
        return name;
    }
  }
}

/// Model representing a marketplace coupon code
class MarketCoupon {
  final String couponCode;
  final String couponName;
  final String created;
  final String? expiryDate;
  final CouponStatus status;
  final CouponDiscountType discountType;
  final double discountValue;
  final double? maxDiscount;
  final double? minPurchase;
  final String currency;
  final String appliesTo; // all, cart, categories, items
  final List<String> categories; // if appliesTo = categories
  final List<String> items; // if appliesTo = items
  final int? maxUses;
  final int? usesPerCustomer;
  final int currentUses;
  final List<String> restrictedUsers; // npubs that cannot use this coupon
  final List<String> allowedUsers; // npubs that can use (empty = all)
  final Map<String, String> descriptions; // language -> description
  final Map<String, String> metadata;

  MarketCoupon({
    required this.couponCode,
    required this.couponName,
    required this.created,
    this.expiryDate,
    this.status = CouponStatus.active,
    this.discountType = CouponDiscountType.fixed,
    required this.discountValue,
    this.maxDiscount,
    this.minPurchase,
    this.currency = 'USD',
    this.appliesTo = 'cart',
    this.categories = const [],
    this.items = const [],
    this.maxUses,
    this.usesPerCustomer,
    this.currentUses = 0,
    this.restrictedUsers = const [],
    this.allowedUsers = const [],
    this.descriptions = const {},
    this.metadata = const {},
  });

  /// Parse timestamp to DateTime
  DateTime get createdDate {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse expiry date to DateTime
  DateTime? get expiryDateTime {
    if (expiryDate == null) return null;
    try {
      final normalized = expiryDate!.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Check if coupon is currently valid
  bool get isValid {
    if (status != CouponStatus.active) return false;
    if (expiryDateTime != null && DateTime.now().isAfter(expiryDateTime!)) {
      return false;
    }
    return hasUsesAvailable;
  }

  /// Check if coupon has expired
  bool get isExpired {
    if (expiryDateTime == null) return false;
    return DateTime.now().isAfter(expiryDateTime!);
  }

  /// Check if uses are available
  bool get hasUsesAvailable {
    if (maxUses == null) return true;
    return currentUses < maxUses!;
  }

  /// Check if user can use this coupon
  bool canUserUse(String userNpub) {
    // Check if user is restricted
    if (restrictedUsers.contains(userNpub)) return false;

    // If allowed users list is empty, all users can use
    if (allowedUsers.isEmpty) return true;

    // Otherwise, user must be in allowed list
    return allowedUsers.contains(userNpub);
  }

  /// Get description for a specific language with fallback
  String? getDescription(String lang) {
    return descriptions[lang.toUpperCase()] ??
           descriptions['EN'] ??
           descriptions.values.firstOrNull;
  }

  /// Export coupon as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('COUPON_CODE: $couponCode');
    buffer.writeln('COUPON_NAME: $couponName');
    buffer.writeln('CREATED: $created');
    if (expiryDate != null) {
      buffer.writeln('EXPIRY_DATE: $expiryDate');
    }
    buffer.writeln('STATUS: ${status.name}');
    buffer.writeln();

    // Discount configuration
    buffer.writeln('DISCOUNT_TYPE: ${discountType.toFileString()}');
    buffer.writeln('DISCOUNT_VALUE: $discountValue');
    if (maxDiscount != null) {
      buffer.writeln('MAX_DISCOUNT: ${maxDiscount!.toStringAsFixed(2)}');
    }
    if (minPurchase != null) {
      buffer.writeln('MIN_PURCHASE: ${minPurchase!.toStringAsFixed(2)}');
    }
    buffer.writeln('CURRENCY: $currency');
    buffer.writeln();

    // Target items
    buffer.writeln('APPLIES_TO: $appliesTo');
    if (appliesTo == 'categories' && categories.isNotEmpty) {
      buffer.writeln('CATEGORIES:');
      for (var category in categories) {
        buffer.writeln('- $category');
      }
    } else if (appliesTo == 'items' && items.isNotEmpty) {
      buffer.writeln('ITEMS:');
      for (var item in items) {
        buffer.writeln('- $item');
      }
    }
    buffer.writeln();

    // Usage limits
    if (maxUses != null) {
      buffer.writeln('MAX_USES: $maxUses');
    }
    if (usesPerCustomer != null) {
      buffer.writeln('USES_PER_CUSTOMER: $usesPerCustomer');
    }
    buffer.writeln('CURRENT_USES: $currentUses');
    buffer.writeln();

    // User restrictions
    if (restrictedUsers.isNotEmpty) {
      buffer.writeln('RESTRICTED_USERS:');
      for (var user in restrictedUsers) {
        buffer.writeln('- $user');
      }
      buffer.writeln();
    }

    if (allowedUsers.isNotEmpty) {
      buffer.writeln('ALLOWED_USERS:');
      for (var user in allowedUsers) {
        buffer.writeln('- $user');
      }
      buffer.writeln();
    }

    // Multilanguage descriptions
    for (var entry in descriptions.entries) {
      buffer.writeln('# DESCRIPTION_${entry.key}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Additional metadata (excluding signature which must be last)
    final regularMetadata = Map<String, String>.from(metadata);
    final sig = regularMetadata.remove('signature');

    for (var entry in regularMetadata.entries) {
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    // Signature must be last if present
    if (sig != null) {
      buffer.writeln('--> signature: $sig');
    }

    return buffer.toString();
  }

  /// Parse coupon from file text
  static MarketCoupon fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty coupon file');
    }

    String? couponCode;
    String? couponName;
    String? created;
    String? expiryDate;
    CouponStatus status = CouponStatus.active;
    CouponDiscountType discountType = CouponDiscountType.fixed;
    double? discountValue;
    double? maxDiscount;
    double? minPurchase;
    String currency = 'USD';
    String appliesTo = 'cart';
    List<String> categories = [];
    List<String> items = [];
    int? maxUses;
    int? usesPerCustomer;
    int currentUses = 0;
    List<String> restrictedUsers = [];
    List<String> allowedUsers = [];
    Map<String, String> descriptions = {};
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('COUPON_CODE: ')) {
        couponCode = line.substring(13).trim();
      } else if (line.startsWith('COUPON_NAME: ')) {
        couponName = line.substring(13).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('EXPIRY_DATE: ')) {
        expiryDate = line.substring(13).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = CouponStatus.fromString(line.substring(8).trim());
      } else if (line.startsWith('DISCOUNT_TYPE: ')) {
        discountType = CouponDiscountType.fromString(line.substring(15).trim());
      } else if (line.startsWith('DISCOUNT_VALUE: ')) {
        discountValue = double.tryParse(line.substring(16).trim());
      } else if (line.startsWith('MAX_DISCOUNT: ')) {
        maxDiscount = double.tryParse(line.substring(14).trim());
      } else if (line.startsWith('MIN_PURCHASE: ')) {
        minPurchase = double.tryParse(line.substring(14).trim());
      } else if (line.startsWith('CURRENCY: ')) {
        currency = line.substring(10).trim();
      } else if (line.startsWith('APPLIES_TO: ')) {
        appliesTo = line.substring(12).trim();
      } else if (line == 'CATEGORIES:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          categories.add(lines[i].substring(2).trim());
          i++;
        }
        continue;
      } else if (line == 'ITEMS:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          items.add(lines[i].substring(2).trim());
          i++;
        }
        continue;
      } else if (line.startsWith('MAX_USES: ')) {
        maxUses = int.tryParse(line.substring(10).trim());
      } else if (line.startsWith('USES_PER_CUSTOMER: ')) {
        usesPerCustomer = int.tryParse(line.substring(19).trim());
      } else if (line.startsWith('CURRENT_USES: ')) {
        currentUses = int.tryParse(line.substring(14).trim()) ?? 0;
      } else if (line == 'RESTRICTED_USERS:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          restrictedUsers.add(lines[i].substring(2).trim());
          i++;
        }
        continue;
      } else if (line == 'ALLOWED_USERS:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          allowedUsers.add(lines[i].substring(2).trim());
          i++;
        }
        continue;
      } else if (line.startsWith('# DESCRIPTION_')) {
        final lang = line.substring(14, line.indexOf(':')).trim();
        final descLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('# ') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            descLines.add(lines[i]);
          }
          i++;
        }
        descriptions[lang] = descLines.join('\n').trim();
        continue;
      } else if (line.startsWith('-->')) {
        final metaLine = line.substring(3).trim();
        final colonIndex = metaLine.indexOf(':');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex).trim();
          final value = metaLine.substring(colonIndex + 1).trim();
          metadata[key] = value;
        }
      }

      i++;
    }

    // Validate required fields
    if (couponCode == null || couponName == null || created == null ||
        discountValue == null) {
      throw Exception('Missing required coupon fields');
    }

    return MarketCoupon(
      couponCode: couponCode,
      couponName: couponName,
      created: created,
      expiryDate: expiryDate,
      status: status,
      discountType: discountType,
      discountValue: discountValue,
      maxDiscount: maxDiscount,
      minPurchase: minPurchase,
      currency: currency,
      appliesTo: appliesTo,
      categories: categories,
      items: items,
      maxUses: maxUses,
      usesPerCustomer: usesPerCustomer,
      currentUses: currentUses,
      restrictedUsers: restrictedUsers,
      allowedUsers: allowedUsers,
      descriptions: descriptions,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketCoupon copyWith({
    String? couponCode,
    String? couponName,
    String? created,
    String? expiryDate,
    CouponStatus? status,
    CouponDiscountType? discountType,
    double? discountValue,
    double? maxDiscount,
    double? minPurchase,
    String? currency,
    String? appliesTo,
    List<String>? categories,
    List<String>? items,
    int? maxUses,
    int? usesPerCustomer,
    int? currentUses,
    List<String>? restrictedUsers,
    List<String>? allowedUsers,
    Map<String, String>? descriptions,
    Map<String, String>? metadata,
  }) {
    return MarketCoupon(
      couponCode: couponCode ?? this.couponCode,
      couponName: couponName ?? this.couponName,
      created: created ?? this.created,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      maxDiscount: maxDiscount ?? this.maxDiscount,
      minPurchase: minPurchase ?? this.minPurchase,
      currency: currency ?? this.currency,
      appliesTo: appliesTo ?? this.appliesTo,
      categories: categories ?? this.categories,
      items: items ?? this.items,
      maxUses: maxUses ?? this.maxUses,
      usesPerCustomer: usesPerCustomer ?? this.usesPerCustomer,
      currentUses: currentUses ?? this.currentUses,
      restrictedUsers: restrictedUsers ?? this.restrictedUsers,
      allowedUsers: allowedUsers ?? this.allowedUsers,
      descriptions: descriptions ?? this.descriptions,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketCoupon(code: $couponCode, name: $couponName, discount: $discountValue${discountType == CouponDiscountType.percentage ? '%' : ' $currency'}, status: ${status.name})';
  }
}
