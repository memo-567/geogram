/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Promotion status
enum PromotionStatus {
  active,
  inactive,
  expired,
  scheduled;

  static PromotionStatus fromString(String value) {
    return PromotionStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PromotionStatus.active,
    );
  }
}

/// Promotion type
enum PromotionType {
  percentage,
  fixed,
  bogo,
  freeShipping;

  static PromotionType fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    return PromotionType.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => PromotionType.percentage,
    );
  }

  String toFileString() {
    switch (this) {
      case PromotionType.freeShipping:
        return 'free-shipping';
      default:
        return name;
    }
  }
}

/// Promotion discount type
enum DiscountType {
  percentage,
  fixed;

  static DiscountType fromString(String value) {
    return DiscountType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => DiscountType.percentage,
    );
  }
}

/// Model representing a marketplace promotion
class MarketPromotion {
  final String promoId;
  final String promoName;
  final String created;
  final String startDate;
  final String endDate;
  final PromotionStatus status;
  final PromotionType type;
  final DiscountType discountType;
  final double discountValue;
  final double? maxDiscount;
  final double? minPurchase;
  final String currency;
  final String appliesTo; // all, categories, items
  final List<String> categories; // if appliesTo = categories
  final List<String> items; // if appliesTo = items
  final int? maxUses;
  final int? usesPerCustomer;
  final int currentUses;
  final Map<String, String> descriptions; // language -> description
  final Map<String, String> metadata;

  MarketPromotion({
    required this.promoId,
    required this.promoName,
    required this.created,
    required this.startDate,
    required this.endDate,
    this.status = PromotionStatus.active,
    this.type = PromotionType.percentage,
    this.discountType = DiscountType.percentage,
    required this.discountValue,
    this.maxDiscount,
    this.minPurchase,
    this.currency = 'USD',
    this.appliesTo = 'all',
    this.categories = const [],
    this.items = const [],
    this.maxUses,
    this.usesPerCustomer,
    this.currentUses = 0,
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

  /// Parse start date to DateTime
  DateTime get startDateTime {
    try {
      final normalized = startDate.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse end date to DateTime
  DateTime get endDateTime {
    try {
      final normalized = endDate.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now().add(const Duration(days: 30));
    }
  }

  /// Check if promotion is currently active
  bool get isCurrentlyActive {
    if (status != PromotionStatus.active) return false;
    final now = DateTime.now();
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  /// Check if promotion has expired
  bool get isExpired {
    return DateTime.now().isAfter(endDateTime);
  }

  /// Check if uses are available
  bool get hasUsesAvailable {
    if (maxUses == null) return true;
    return currentUses < maxUses!;
  }

  /// Get description for a specific language with fallback
  String? getDescription(String lang) {
    return descriptions[lang.toUpperCase()] ??
           descriptions['EN'] ??
           descriptions.values.firstOrNull;
  }

  /// Export promotion as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('PROMO_ID: $promoId');
    buffer.writeln('PROMO_NAME: $promoName');
    buffer.writeln('CREATED: $created');
    buffer.writeln('START_DATE: $startDate');
    buffer.writeln('END_DATE: $endDate');
    buffer.writeln('STATUS: ${status.name}');
    buffer.writeln('TYPE: ${type.toFileString()}');
    buffer.writeln();

    // Discount configuration
    buffer.writeln('DISCOUNT_TYPE: ${discountType.name}');
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

  /// Parse promotion from file text
  static MarketPromotion fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty promotion file');
    }

    String? promoId;
    String? promoName;
    String? created;
    String? startDate;
    String? endDate;
    PromotionStatus status = PromotionStatus.active;
    PromotionType type = PromotionType.percentage;
    DiscountType discountType = DiscountType.percentage;
    double? discountValue;
    double? maxDiscount;
    double? minPurchase;
    String currency = 'USD';
    String appliesTo = 'all';
    List<String> categories = [];
    List<String> items = [];
    int? maxUses;
    int? usesPerCustomer;
    int currentUses = 0;
    Map<String, String> descriptions = {};
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('PROMO_ID: ')) {
        promoId = line.substring(10).trim();
      } else if (line.startsWith('PROMO_NAME: ')) {
        promoName = line.substring(12).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('START_DATE: ')) {
        startDate = line.substring(12).trim();
      } else if (line.startsWith('END_DATE: ')) {
        endDate = line.substring(10).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = PromotionStatus.fromString(line.substring(8).trim());
      } else if (line.startsWith('TYPE: ')) {
        type = PromotionType.fromString(line.substring(6).trim());
      } else if (line.startsWith('DISCOUNT_TYPE: ')) {
        discountType = DiscountType.fromString(line.substring(15).trim());
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
    if (promoId == null || promoName == null || created == null ||
        startDate == null || endDate == null || discountValue == null) {
      throw Exception('Missing required promotion fields');
    }

    return MarketPromotion(
      promoId: promoId,
      promoName: promoName,
      created: created,
      startDate: startDate,
      endDate: endDate,
      status: status,
      type: type,
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
      descriptions: descriptions,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketPromotion copyWith({
    String? promoId,
    String? promoName,
    String? created,
    String? startDate,
    String? endDate,
    PromotionStatus? status,
    PromotionType? type,
    DiscountType? discountType,
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
    Map<String, String>? descriptions,
    Map<String, String>? metadata,
  }) {
    return MarketPromotion(
      promoId: promoId ?? this.promoId,
      promoName: promoName ?? this.promoName,
      created: created ?? this.created,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      type: type ?? this.type,
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
      descriptions: descriptions ?? this.descriptions,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketPromotion(id: $promoId, name: $promoName, discount: $discountValue${discountType == DiscountType.percentage ? '%' : ' $currency'}, status: ${status.name})';
  }
}
