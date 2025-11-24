/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Cart status
enum CartStatus {
  active,
  checkout,
  converted,
  abandoned,
  expired;

  static CartStatus fromString(String value) {
    return CartStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => CartStatus.active,
    );
  }
}

/// Cart item representation
class CartItem {
  final String itemId;
  final int quantity;
  final double price;
  final double subtotal;

  CartItem({
    required this.itemId,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });

  /// Parse from line format: "item-abc123 | qty: 2 | price: 35.00 | subtotal: 70.00"
  static CartItem fromLine(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.length < 4) {
      throw Exception('Invalid cart item line');
    }

    final itemId = parts[0];
    final qty = int.parse(parts[1].replaceFirst('qty:', '').trim());
    final price = double.parse(parts[2].replaceFirst('price:', '').trim());
    final subtotal = double.parse(parts[3].replaceFirst('subtotal:', '').trim());

    return CartItem(
      itemId: itemId,
      quantity: qty,
      price: price,
      subtotal: subtotal,
    );
  }

  /// Export to line format
  String toLine() {
    return '$itemId | qty: $quantity | price: ${price.toStringAsFixed(2)} | subtotal: ${subtotal.toStringAsFixed(2)}';
  }
}

/// Applied promotion
class AppliedPromotion {
  final String promoId;
  final String discount; // e.g., "10%" or "15.00"
  final double savings;

  AppliedPromotion({
    required this.promoId,
    required this.discount,
    required this.savings,
  });

  /// Parse from line format: "promo-black-friday-2025 | discount: 10% | savings: 10.90"
  static AppliedPromotion fromLine(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.length < 3) {
      throw Exception('Invalid promotion line');
    }

    final promoId = parts[0];
    final discount = parts[1].replaceFirst('discount:', '').trim();
    final savings = double.parse(parts[2].replaceFirst('savings:', '').trim());

    return AppliedPromotion(
      promoId: promoId,
      discount: discount,
      savings: savings,
    );
  }

  /// Export to line format
  String toLine() {
    return '$promoId | discount: $discount | savings: ${savings.toStringAsFixed(2)}';
  }
}

/// Applied coupon
class AppliedCoupon {
  final String code;
  final double discount;

  AppliedCoupon({
    required this.code,
    required this.discount,
  });

  /// Parse from line format: "WELCOME10 | discount: 10.00"
  static AppliedCoupon fromLine(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.length < 2) {
      throw Exception('Invalid coupon line');
    }

    final code = parts[0];
    final discount = double.parse(parts[1].replaceFirst('discount:', '').trim());

    return AppliedCoupon(
      code: code,
      discount: discount,
    );
  }

  /// Export to line format
  String toLine() {
    return '$code | discount: ${discount.toStringAsFixed(2)}';
  }
}

/// Model representing a shopping cart
class MarketCart {
  final String cartId;
  final String buyerCallsign;
  final String buyerNpub;
  final String created;
  final String updated;
  final CartStatus status;
  final List<CartItem> items;
  final List<AppliedPromotion> promotions;
  final List<AppliedCoupon> coupons;
  final double itemsSubtotal;
  final double promotionDiscount;
  final double couponDiscount;
  final double subtotal;
  final double shippingEstimate;
  final double taxEstimate;
  final double estimatedTotal;
  final String currency;
  final String? notes;
  final String? convertedToOrder;
  final String? conversionDate;
  final Map<String, String> metadata;

  MarketCart({
    required this.cartId,
    required this.buyerCallsign,
    required this.buyerNpub,
    required this.created,
    required this.updated,
    this.status = CartStatus.active,
    this.items = const [],
    this.promotions = const [],
    this.coupons = const [],
    this.itemsSubtotal = 0.0,
    this.promotionDiscount = 0.0,
    this.couponDiscount = 0.0,
    this.subtotal = 0.0,
    this.shippingEstimate = 0.0,
    this.taxEstimate = 0.0,
    this.estimatedTotal = 0.0,
    this.currency = 'USD',
    this.notes,
    this.convertedToOrder,
    this.conversionDate,
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

  /// Check if cart is signed with NOSTR
  bool get isSigned => metadata.containsKey('signature');

  /// Check if cart is active
  bool get isActive => status == CartStatus.active;

  /// Check if cart has been converted to order
  bool get isConverted => status == CartStatus.converted;

  /// Get total item count
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  /// Export cart as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('CART_ID: $cartId');
    buffer.writeln('BUYER_CALLSIGN: $buyerCallsign');
    buffer.writeln('BUYER_NPUB: $buyerNpub');
    buffer.writeln('CREATED: $created');
    buffer.writeln('UPDATED: $updated');
    buffer.writeln('STATUS: ${status.name}');
    buffer.writeln();

    // Cart items
    if (items.isNotEmpty) {
      buffer.writeln('ITEMS:');
      for (var item in items) {
        buffer.writeln('- ${item.toLine()}');
      }
      buffer.writeln();
    }

    // Applied promotions
    if (promotions.isNotEmpty) {
      buffer.writeln('PROMOTIONS:');
      for (var promo in promotions) {
        buffer.writeln('- ${promo.toLine()}');
      }
      buffer.writeln();
    }

    // Applied coupons
    if (coupons.isNotEmpty) {
      buffer.writeln('COUPONS:');
      for (var coupon in coupons) {
        buffer.writeln('- ${coupon.toLine()}');
      }
      buffer.writeln();
    }

    // Pricing summary
    buffer.writeln('ITEMS_SUBTOTAL: ${itemsSubtotal.toStringAsFixed(2)}');
    buffer.writeln('PROMOTION_DISCOUNT: ${promotionDiscount.toStringAsFixed(2)}');
    buffer.writeln('COUPON_DISCOUNT: ${couponDiscount.toStringAsFixed(2)}');
    buffer.writeln('SUBTOTAL: ${subtotal.toStringAsFixed(2)}');
    buffer.writeln('SHIPPING_ESTIMATE: ${shippingEstimate.toStringAsFixed(2)}');
    buffer.writeln('TAX_ESTIMATE: ${taxEstimate.toStringAsFixed(2)}');
    buffer.writeln('ESTIMATED_TOTAL: ${estimatedTotal.toStringAsFixed(2)}');
    buffer.writeln('CURRENCY: $currency');
    buffer.writeln();

    // Optional notes
    if (notes != null && notes!.isNotEmpty) {
      buffer.writeln('NOTES:');
      buffer.writeln(notes);
      buffer.writeln();
    }

    // Conversion info
    if (convertedToOrder != null) {
      buffer.writeln('CONVERTED_TO_ORDER: $convertedToOrder');
      if (conversionDate != null) {
        buffer.writeln('CONVERSION_DATE: $conversionDate');
      }
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

  /// Parse cart from file text
  static MarketCart fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty cart file');
    }

    String? cartId;
    String? buyerCallsign;
    String? buyerNpub;
    String? created;
    String? updated;
    CartStatus status = CartStatus.active;
    List<CartItem> items = [];
    List<AppliedPromotion> promotions = [];
    List<AppliedCoupon> coupons = [];
    double itemsSubtotal = 0.0;
    double promotionDiscount = 0.0;
    double couponDiscount = 0.0;
    double subtotal = 0.0;
    double shippingEstimate = 0.0;
    double taxEstimate = 0.0;
    double estimatedTotal = 0.0;
    String currency = 'USD';
    String? notes;
    String? convertedToOrder;
    String? conversionDate;
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('CART_ID: ')) {
        cartId = line.substring(9).trim();
      } else if (line.startsWith('BUYER_CALLSIGN: ')) {
        buyerCallsign = line.substring(16).trim();
      } else if (line.startsWith('BUYER_NPUB: ')) {
        buyerNpub = line.substring(12).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('UPDATED: ')) {
        updated = line.substring(9).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = CartStatus.fromString(line.substring(8).trim());
      } else if (line == 'ITEMS:') {
        // Parse cart items
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          items.add(CartItem.fromLine(lines[i].substring(2)));
          i++;
        }
        continue;
      } else if (line == 'PROMOTIONS:') {
        // Parse promotions
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          promotions.add(AppliedPromotion.fromLine(lines[i].substring(2)));
          i++;
        }
        continue;
      } else if (line == 'COUPONS:') {
        // Parse coupons
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          coupons.add(AppliedCoupon.fromLine(lines[i].substring(2)));
          i++;
        }
        continue;
      } else if (line.startsWith('ITEMS_SUBTOTAL: ')) {
        itemsSubtotal = double.tryParse(line.substring(16).trim()) ?? 0.0;
      } else if (line.startsWith('PROMOTION_DISCOUNT: ')) {
        promotionDiscount = double.tryParse(line.substring(20).trim()) ?? 0.0;
      } else if (line.startsWith('COUPON_DISCOUNT: ')) {
        couponDiscount = double.tryParse(line.substring(17).trim()) ?? 0.0;
      } else if (line.startsWith('SUBTOTAL: ')) {
        subtotal = double.tryParse(line.substring(10).trim()) ?? 0.0;
      } else if (line.startsWith('SHIPPING_ESTIMATE: ')) {
        shippingEstimate = double.tryParse(line.substring(19).trim()) ?? 0.0;
      } else if (line.startsWith('TAX_ESTIMATE: ')) {
        taxEstimate = double.tryParse(line.substring(14).trim()) ?? 0.0;
      } else if (line.startsWith('ESTIMATED_TOTAL: ')) {
        estimatedTotal = double.tryParse(line.substring(17).trim()) ?? 0.0;
      } else if (line.startsWith('CURRENCY: ')) {
        currency = line.substring(10).trim();
      } else if (line == 'NOTES:') {
        // Parse multi-line notes
        final notesLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('CONVERTED_TO_ORDER:') &&
               !lines[i].startsWith('CONVERSION_DATE:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            notesLines.add(lines[i]);
          }
          i++;
        }
        notes = notesLines.join('\n').trim();
        continue;
      } else if (line.startsWith('CONVERTED_TO_ORDER: ')) {
        convertedToOrder = line.substring(20).trim();
      } else if (line.startsWith('CONVERSION_DATE: ')) {
        conversionDate = line.substring(17).trim();
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
    if (cartId == null || buyerCallsign == null || buyerNpub == null ||
        created == null || updated == null) {
      throw Exception('Missing required cart fields');
    }

    return MarketCart(
      cartId: cartId,
      buyerCallsign: buyerCallsign,
      buyerNpub: buyerNpub,
      created: created,
      updated: updated,
      status: status,
      items: items,
      promotions: promotions,
      coupons: coupons,
      itemsSubtotal: itemsSubtotal,
      promotionDiscount: promotionDiscount,
      couponDiscount: couponDiscount,
      subtotal: subtotal,
      shippingEstimate: shippingEstimate,
      taxEstimate: taxEstimate,
      estimatedTotal: estimatedTotal,
      currency: currency,
      notes: notes,
      convertedToOrder: convertedToOrder,
      conversionDate: conversionDate,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketCart copyWith({
    String? cartId,
    String? buyerCallsign,
    String? buyerNpub,
    String? created,
    String? updated,
    CartStatus? status,
    List<CartItem>? items,
    List<AppliedPromotion>? promotions,
    List<AppliedCoupon>? coupons,
    double? itemsSubtotal,
    double? promotionDiscount,
    double? couponDiscount,
    double? subtotal,
    double? shippingEstimate,
    double? taxEstimate,
    double? estimatedTotal,
    String? currency,
    String? notes,
    String? convertedToOrder,
    String? conversionDate,
    Map<String, String>? metadata,
  }) {
    return MarketCart(
      cartId: cartId ?? this.cartId,
      buyerCallsign: buyerCallsign ?? this.buyerCallsign,
      buyerNpub: buyerNpub ?? this.buyerNpub,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      status: status ?? this.status,
      items: items ?? this.items,
      promotions: promotions ?? this.promotions,
      coupons: coupons ?? this.coupons,
      itemsSubtotal: itemsSubtotal ?? this.itemsSubtotal,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      couponDiscount: couponDiscount ?? this.couponDiscount,
      subtotal: subtotal ?? this.subtotal,
      shippingEstimate: shippingEstimate ?? this.shippingEstimate,
      taxEstimate: taxEstimate ?? this.taxEstimate,
      estimatedTotal: estimatedTotal ?? this.estimatedTotal,
      currency: currency ?? this.currency,
      notes: notes ?? this.notes,
      convertedToOrder: convertedToOrder ?? this.convertedToOrder,
      conversionDate: conversionDate ?? this.conversionDate,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketCart(id: $cartId, buyer: $buyerCallsign, items: ${items.length}, status: ${status.name})';
  }
}
