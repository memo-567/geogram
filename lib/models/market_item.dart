/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Item status
enum ItemStatus {
  available,
  outOfStock,
  lowStock,
  discontinued,
  preOrder,
  draft;

  static ItemStatus fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '');
    return ItemStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => ItemStatus.draft,
    );
  }

  String toFileString() {
    switch (this) {
      case ItemStatus.outOfStock:
        return 'out-of-stock';
      case ItemStatus.lowStock:
        return 'low-stock';
      case ItemStatus.preOrder:
        return 'pre-order';
      default:
        return name;
    }
  }
}

/// Item type
enum ItemType {
  physical,
  digital,
  service;

  static ItemType fromString(String value) {
    return ItemType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => ItemType.physical,
    );
  }
}

/// Delivery method
enum DeliveryMethod {
  physical,
  digital,
  inPerson,
  online;

  static DeliveryMethod fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '');
    return DeliveryMethod.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => DeliveryMethod.physical,
    );
  }

  String toFileString() {
    switch (this) {
      case DeliveryMethod.inPerson:
        return 'in-person';
      default:
        return name;
    }
  }
}

/// Model representing a marketplace item
class MarketItem {
  final String itemId;
  final String created;
  final String updated;
  final ItemStatus status;
  final ItemType type;
  final DeliveryMethod deliveryMethod;

  // Geographic availability (REQUIRED)
  final String location;
  final double latitude;
  final double longitude;
  final int radius; // 1-200 km
  final String radiusUnit;

  // Basic info
  final String? sku;
  final String? brand;
  final String? model;

  // Multilanguage titles
  final Map<String, String> titles; // language -> title

  // Pricing
  final dynamic price; // Can be 'free', number, or null
  final String currency;
  final dynamic stock; // Can be 'unlimited' or number
  final int sold;
  final int minOrder;
  final int maxOrder;

  // Ratings
  final double rating;
  final int reviewCount;

  // Multilanguage content
  final Map<String, String> descriptions; // language -> description
  final Map<String, String> specifications; // language -> specifications

  // Shipping information
  final int? weight;
  final String? weightUnit;
  final String? dimensions; // e.g., "12x8x5"
  final String? dimensionsUnit;
  final String? shippingTime;
  final String? shipsFrom;

  // Category (derived from folder path, not stored)
  final String? categoryPath;

  // Media files
  final List<String> galleryFiles;

  // Metadata
  final Map<String, String> metadata;

  MarketItem({
    required this.itemId,
    required this.created,
    required this.updated,
    this.status = ItemStatus.draft,
    this.type = ItemType.physical,
    this.deliveryMethod = DeliveryMethod.physical,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.radiusUnit = 'km',
    this.sku,
    this.brand,
    this.model,
    this.titles = const {},
    this.price,
    this.currency = 'USD',
    this.stock,
    this.sold = 0,
    this.minOrder = 1,
    this.maxOrder = 1,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.descriptions = const {},
    this.specifications = const {},
    this.weight,
    this.weightUnit,
    this.dimensions,
    this.dimensionsUnit,
    this.shippingTime,
    this.shipsFrom,
    this.categoryPath,
    this.galleryFiles = const [],
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

  /// Parse updated timestamp to DateTime
  DateTime get updatedDate {
    try {
      final normalized = updated.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get NOSTR public key
  String? get npub => metadata['npub'];

  /// Get signature
  String? get signature => metadata['signature'];

  /// Check if item is signed with NOSTR
  bool get isSigned => metadata.containsKey('signature');

  /// Check if item is available for purchase
  bool get isAvailable => status == ItemStatus.available;

  /// Check if item is free
  bool get isFree => price == 'free' || price == 0 || price == 0.0;

  /// Check if stock is unlimited
  bool get isUnlimitedStock => stock == 'unlimited';

  /// Get numeric stock value
  int? get numericStock {
    if (stock == null || stock == 'unlimited') return null;
    if (stock is int) return stock as int;
    if (stock is String) return int.tryParse(stock as String);
    return null;
  }

  /// Get numeric price value
  double? get numericPrice {
    if (price == null || price == 'free') return 0.0;
    if (price is double) return price as double;
    if (price is int) return (price as int).toDouble();
    if (price is String) return double.tryParse(price as String);
    return null;
  }

  /// Get formatted price string
  String get formattedPrice {
    if (isFree) return 'Free';
    final p = numericPrice;
    if (p == null) return 'N/A';
    return '$currency ${p.toStringAsFixed(2)}';
  }

  /// Get title for a specific language with fallback
  String? getTitle(String lang) {
    return titles[lang.toUpperCase()] ??
           titles['EN'] ??
           titles.values.firstOrNull;
  }

  /// Get description for a specific language with fallback
  String? getDescription(String lang) {
    return descriptions[lang.toUpperCase()] ??
           descriptions['EN'] ??
           descriptions.values.firstOrNull;
  }

  /// Get specifications for a specific language with fallback
  String? getSpecifications(String lang) {
    return specifications[lang.toUpperCase()] ??
           specifications['EN'] ??
           specifications.values.firstOrNull;
  }

  /// Export item as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('ITEM_ID: $itemId');
    buffer.writeln('CREATED: $created');
    buffer.writeln('UPDATED: $updated');
    buffer.writeln('STATUS: ${status.toFileString()}');
    buffer.writeln('TYPE: ${type.name}');
    buffer.writeln('DELIVERY_METHOD: ${deliveryMethod.toFileString()}');
    buffer.writeln();

    // Geographic availability
    buffer.writeln('LOCATION: $location');
    buffer.writeln('LATITUDE: $latitude');
    buffer.writeln('LONGITUDE: $longitude');
    buffer.writeln('RADIUS: $radius');
    buffer.writeln('RADIUS_UNIT: $radiusUnit');
    buffer.writeln();

    // Basic info
    if (sku != null && sku!.isNotEmpty) {
      buffer.writeln('SKU: $sku');
    }
    if (brand != null && brand!.isNotEmpty) {
      buffer.writeln('BRAND: $brand');
    }
    if (model != null && model!.isNotEmpty) {
      buffer.writeln('MODEL: $model');
    }
    if (sku != null || brand != null || model != null) {
      buffer.writeln();
    }

    // Multilanguage titles
    for (var entry in titles.entries) {
      buffer.writeln('# TITLE_${entry.key}: ${entry.value}');
    }
    if (titles.isNotEmpty) {
      buffer.writeln();
    }

    // Pricing
    if (price != null) {
      buffer.writeln('PRICE: $price');
    }
    buffer.writeln('CURRENCY: $currency');
    if (stock != null) {
      buffer.writeln('STOCK: $stock');
    }
    buffer.writeln('SOLD: $sold');
    buffer.writeln('MIN_ORDER: $minOrder');
    buffer.writeln('MAX_ORDER: $maxOrder');
    buffer.writeln();

    // Ratings
    if (rating > 0 || reviewCount > 0) {
      buffer.writeln('RATING: ${rating.toStringAsFixed(1)}');
      buffer.writeln('REVIEW_COUNT: $reviewCount');
      buffer.writeln();
    }

    // Multilanguage descriptions
    for (var entry in descriptions.entries) {
      buffer.writeln('[${entry.key}]');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Specifications
    for (var entry in specifications.entries) {
      buffer.writeln('SPECIFICATIONS_${entry.key}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Shipping information
    if (weight != null) {
      buffer.writeln('WEIGHT: $weight');
      if (weightUnit != null) {
        buffer.writeln('WEIGHT_UNIT: $weightUnit');
      }
    }
    if (dimensions != null && dimensions!.isNotEmpty) {
      buffer.writeln('DIMENSIONS: $dimensions');
      if (dimensionsUnit != null) {
        buffer.writeln('DIMENSIONS_UNIT: $dimensionsUnit');
      }
    }
    if (shippingTime != null && shippingTime!.isNotEmpty) {
      buffer.writeln('SHIPPING_TIME: $shippingTime');
    }
    if (shipsFrom != null && shipsFrom!.isNotEmpty) {
      buffer.writeln('SHIPS_FROM: $shipsFrom');
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

  /// Parse item from file text
  static MarketItem fromText(String text, String itemId, {String? categoryPath}) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty item file');
    }

    String? created;
    String? updated;
    ItemStatus status = ItemStatus.draft;
    ItemType type = ItemType.physical;
    DeliveryMethod deliveryMethod = DeliveryMethod.physical;
    String? location;
    double? latitude;
    double? longitude;
    int? radius;
    String radiusUnit = 'km';
    String? sku;
    String? brand;
    String? model;
    Map<String, String> titles = {};
    dynamic price;
    String currency = 'USD';
    dynamic stock;
    int sold = 0;
    int minOrder = 1;
    int maxOrder = 1;
    double rating = 0.0;
    int reviewCount = 0;
    Map<String, String> descriptions = {};
    Map<String, String> specifications = {};
    int? weight;
    String? weightUnit;
    String? dimensions;
    String? dimensionsUnit;
    String? shippingTime;
    String? shipsFrom;
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('ITEM_ID: ')) {
        // itemId already provided as parameter
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('UPDATED: ')) {
        updated = line.substring(9).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = ItemStatus.fromString(line.substring(8).trim());
      } else if (line.startsWith('TYPE: ')) {
        type = ItemType.fromString(line.substring(6).trim());
      } else if (line.startsWith('DELIVERY_METHOD: ')) {
        deliveryMethod = DeliveryMethod.fromString(line.substring(17).trim());
      } else if (line.startsWith('LOCATION: ')) {
        location = line.substring(10).trim();
      } else if (line.startsWith('LATITUDE: ')) {
        latitude = double.tryParse(line.substring(10).trim());
      } else if (line.startsWith('LONGITUDE: ')) {
        longitude = double.tryParse(line.substring(11).trim());
      } else if (line.startsWith('RADIUS: ')) {
        radius = int.tryParse(line.substring(8).trim());
      } else if (line.startsWith('RADIUS_UNIT: ')) {
        radiusUnit = line.substring(13).trim();
      } else if (line.startsWith('SKU: ')) {
        sku = line.substring(5).trim();
      } else if (line.startsWith('BRAND: ')) {
        brand = line.substring(7).trim();
      } else if (line.startsWith('MODEL: ')) {
        model = line.substring(7).trim();
      } else if (line.startsWith('# TITLE_')) {
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          final lang = line.substring(8, colonIndex).trim();
          final title = line.substring(colonIndex + 1).trim();
          titles[lang] = title;
        }
      } else if (line.startsWith('PRICE: ')) {
        final priceStr = line.substring(7).trim();
        if (priceStr.toLowerCase() == 'free') {
          price = 'free';
        } else {
          price = double.tryParse(priceStr) ?? priceStr;
        }
      } else if (line.startsWith('CURRENCY: ')) {
        currency = line.substring(10).trim();
      } else if (line.startsWith('STOCK: ')) {
        final stockStr = line.substring(7).trim();
        if (stockStr.toLowerCase() == 'unlimited') {
          stock = 'unlimited';
        } else {
          stock = int.tryParse(stockStr) ?? stockStr;
        }
      } else if (line.startsWith('SOLD: ')) {
        sold = int.tryParse(line.substring(6).trim()) ?? 0;
      } else if (line.startsWith('MIN_ORDER: ')) {
        minOrder = int.tryParse(line.substring(11).trim()) ?? 1;
      } else if (line.startsWith('MAX_ORDER: ')) {
        maxOrder = int.tryParse(line.substring(11).trim()) ?? 1;
      } else if (line.startsWith('RATING: ')) {
        rating = double.tryParse(line.substring(8).trim()) ?? 0.0;
      } else if (line.startsWith('REVIEW_COUNT: ')) {
        reviewCount = int.tryParse(line.substring(14).trim()) ?? 0;
      } else if (line.startsWith('[') && line.endsWith(']')) {
        // Parse multilanguage description
        final lang = line.substring(1, line.length - 1).trim();
        final descLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('[') &&
               !lines[i].startsWith('SPECIFICATIONS_') &&
               !lines[i].startsWith('WEIGHT:') &&
               !lines[i].startsWith('DIMENSIONS:') &&
               !lines[i].startsWith('SHIPPING_TIME:') &&
               !lines[i].startsWith('SHIPS_FROM:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            descLines.add(lines[i]);
          }
          i++;
        }
        descriptions[lang] = descLines.join('\n').trim();
        continue;
      } else if (line.startsWith('SPECIFICATIONS_')) {
        final colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          final lang = line.substring(15, colonIndex).trim();
          final specLines = <String>[];
          i++;
          while (i < lines.length && !lines[i].startsWith('[') &&
                 !lines[i].startsWith('SPECIFICATIONS_') &&
                 !lines[i].startsWith('WEIGHT:') &&
                 !lines[i].startsWith('DIMENSIONS:') &&
                 !lines[i].startsWith('SHIPPING_TIME:') &&
                 !lines[i].startsWith('SHIPS_FROM:') &&
                 !lines[i].startsWith('-->')) {
            if (lines[i].trim().isNotEmpty) {
              specLines.add(lines[i]);
            }
            i++;
          }
          specifications[lang] = specLines.join('\n').trim();
          continue;
        }
      } else if (line.startsWith('WEIGHT: ')) {
        weight = int.tryParse(line.substring(8).trim());
      } else if (line.startsWith('WEIGHT_UNIT: ')) {
        weightUnit = line.substring(13).trim();
      } else if (line.startsWith('DIMENSIONS: ')) {
        dimensions = line.substring(12).trim();
      } else if (line.startsWith('DIMENSIONS_UNIT: ')) {
        dimensionsUnit = line.substring(17).trim();
      } else if (line.startsWith('SHIPPING_TIME: ')) {
        shippingTime = line.substring(15).trim();
      } else if (line.startsWith('SHIPS_FROM: ')) {
        shipsFrom = line.substring(12).trim();
      } else if (line.startsWith('-->')) {
        // Parse metadata
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
    if (created == null || updated == null || location == null ||
        latitude == null || longitude == null || radius == null) {
      throw Exception('Missing required item fields');
    }

    return MarketItem(
      itemId: itemId,
      created: created,
      updated: updated,
      status: status,
      type: type,
      deliveryMethod: deliveryMethod,
      location: location,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      radiusUnit: radiusUnit,
      sku: sku,
      brand: brand,
      model: model,
      titles: titles,
      price: price,
      currency: currency,
      stock: stock,
      sold: sold,
      minOrder: minOrder,
      maxOrder: maxOrder,
      rating: rating,
      reviewCount: reviewCount,
      descriptions: descriptions,
      specifications: specifications,
      weight: weight,
      weightUnit: weightUnit,
      dimensions: dimensions,
      dimensionsUnit: dimensionsUnit,
      shippingTime: shippingTime,
      shipsFrom: shipsFrom,
      categoryPath: categoryPath,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketItem copyWith({
    String? itemId,
    String? created,
    String? updated,
    ItemStatus? status,
    ItemType? type,
    DeliveryMethod? deliveryMethod,
    String? location,
    double? latitude,
    double? longitude,
    int? radius,
    String? radiusUnit,
    String? sku,
    String? brand,
    String? model,
    Map<String, String>? titles,
    dynamic price,
    String? currency,
    dynamic stock,
    int? sold,
    int? minOrder,
    int? maxOrder,
    double? rating,
    int? reviewCount,
    Map<String, String>? descriptions,
    Map<String, String>? specifications,
    int? weight,
    String? weightUnit,
    String? dimensions,
    String? dimensionsUnit,
    String? shippingTime,
    String? shipsFrom,
    String? categoryPath,
    List<String>? galleryFiles,
    Map<String, String>? metadata,
  }) {
    return MarketItem(
      itemId: itemId ?? this.itemId,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      status: status ?? this.status,
      type: type ?? this.type,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      radiusUnit: radiusUnit ?? this.radiusUnit,
      sku: sku ?? this.sku,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      titles: titles ?? this.titles,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      stock: stock ?? this.stock,
      sold: sold ?? this.sold,
      minOrder: minOrder ?? this.minOrder,
      maxOrder: maxOrder ?? this.maxOrder,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      descriptions: descriptions ?? this.descriptions,
      specifications: specifications ?? this.specifications,
      weight: weight ?? this.weight,
      weightUnit: weightUnit ?? this.weightUnit,
      dimensions: dimensions ?? this.dimensions,
      dimensionsUnit: dimensionsUnit ?? this.dimensionsUnit,
      shippingTime: shippingTime ?? this.shippingTime,
      shipsFrom: shipsFrom ?? this.shipsFrom,
      categoryPath: categoryPath ?? this.categoryPath,
      galleryFiles: galleryFiles ?? this.galleryFiles,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketItem(id: $itemId, status: ${status.toFileString()}, type: ${type.name})';
  }
}
