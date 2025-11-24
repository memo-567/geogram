/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'market_cart.dart'; // Reuse CartItem, AppliedPromotion, AppliedCoupon

/// Order status (canonical)
enum OrderStatus {
  requested,
  confirmed,
  paid,
  processing,
  shipped,
  inTransit,
  delivered,
  completed,
  cancelled,
  refundRequested,
  refunded,
  disputed;

  static OrderStatus fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '');
    return OrderStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => OrderStatus.requested,
    );
  }

  String toFileString() {
    switch (this) {
      case OrderStatus.inTransit:
        return 'in-transit';
      case OrderStatus.refundRequested:
        return 'refund-requested';
      default:
        return name;
    }
  }
}

/// Buyer status
enum BuyerStatus {
  awaitingConfirmation,
  awaitingPayment,
  paymentProcessing,
  orderConfirmed,
  awaitingShipment,
  inTransit,
  delivered,
  completed,
  refundRequested,
  refundProcessing,
  refunded,
  cancelled,
  disputed;

  static BuyerStatus fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '');
    return BuyerStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => BuyerStatus.awaitingConfirmation,
    );
  }

  String toFileString() {
    switch (this) {
      case BuyerStatus.awaitingConfirmation:
        return 'awaiting-confirmation';
      case BuyerStatus.awaitingPayment:
        return 'awaiting-payment';
      case BuyerStatus.paymentProcessing:
        return 'payment-processing';
      case BuyerStatus.orderConfirmed:
        return 'order-confirmed';
      case BuyerStatus.awaitingShipment:
        return 'awaiting-shipment';
      case BuyerStatus.inTransit:
        return 'in-transit';
      case BuyerStatus.refundRequested:
        return 'refund-requested';
      case BuyerStatus.refundProcessing:
        return 'refund-processing';
      default:
        return name;
    }
  }
}

/// Seller status
enum SellerStatus {
  reviewOrder,
  awaitingPayment,
  paymentReceived,
  prepareShipment,
  readyToShip,
  shipped,
  inTransit,
  delivered,
  completed,
  refundRequested,
  processingRefund,
  refunded,
  cancelled,
  disputed;

  static SellerStatus fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('-', '');
    return SellerStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => SellerStatus.reviewOrder,
    );
  }

  String toFileString() {
    switch (this) {
      case SellerStatus.reviewOrder:
        return 'review-order';
      case SellerStatus.awaitingPayment:
        return 'awaiting-payment';
      case SellerStatus.paymentReceived:
        return 'payment-received';
      case SellerStatus.prepareShipment:
        return 'prepare-shipment';
      case SellerStatus.readyToShip:
        return 'ready-to-ship';
      case SellerStatus.inTransit:
        return 'in-transit';
      case SellerStatus.refundRequested:
        return 'refund-requested';
      case SellerStatus.processingRefund:
        return 'processing-refund';
      default:
        return name;
    }
  }
}

/// Payment status
enum PaymentStatus {
  pending,
  processing,
  completed,
  failed,
  refunded;

  static PaymentStatus fromString(String value) {
    return PaymentStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PaymentStatus.pending,
    );
  }
}

/// Status history entry
class StatusHistoryEntry {
  final String timestamp;
  final String status;
  final String description;

  StatusHistoryEntry({
    required this.timestamp,
    required this.status,
    required this.description,
  });

  /// Parse from line format: "2025-11-22 16:30_00 | requested | Order placed by buyer"
  static StatusHistoryEntry fromLine(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    if (parts.length < 3) {
      throw Exception('Invalid status history line');
    }

    return StatusHistoryEntry(
      timestamp: parts[0],
      status: parts[1],
      description: parts[2],
    );
  }

  /// Export to line format
  String toLine() {
    return '$timestamp | $status | $description';
  }
}

/// Model representing a marketplace order
class MarketOrder {
  final String orderId;
  final String buyerCallsign;
  final String buyerNpub;
  final String sellerCallsign;
  final String sellerNpub;
  final String created;
  final OrderStatus status;
  final BuyerStatus buyerStatus;
  final SellerStatus sellerStatus;

  // Order items (reuse from cart)
  final List<CartItem> items;
  final List<AppliedPromotion> promotions;
  final List<AppliedCoupon> coupons;

  // Pricing
  final double itemsSubtotal;
  final double promotionDiscount;
  final double couponDiscount;
  final double subtotal;
  final double shipping;
  final String? taxId;
  final int? taxPercentage;
  final double taxAmount;
  final double total;
  final String currency;

  // Payment information
  final String paymentMethod;
  final String? paymentAddress;
  final double? paymentAmount;
  final PaymentStatus paymentStatus;

  // Shipping information
  final String? shippingMethod;
  final String? shippingName;
  final String? shippingAddress;
  final String? shippingPostal;
  final String? shippingCountry;
  final String? shippingPhone;

  // Status history
  final List<StatusHistoryEntry> statusHistory;

  // Notes
  final String? buyerNotes;
  final String? sellerNotes;

  // Receipt info (for completed orders)
  final String? receiptNumber;
  final String? receiptDate;

  // Metadata
  final Map<String, String> metadata;

  MarketOrder({
    required this.orderId,
    required this.buyerCallsign,
    required this.buyerNpub,
    required this.sellerCallsign,
    required this.sellerNpub,
    required this.created,
    this.status = OrderStatus.requested,
    this.buyerStatus = BuyerStatus.awaitingConfirmation,
    this.sellerStatus = SellerStatus.reviewOrder,
    this.items = const [],
    this.promotions = const [],
    this.coupons = const [],
    this.itemsSubtotal = 0.0,
    this.promotionDiscount = 0.0,
    this.couponDiscount = 0.0,
    this.subtotal = 0.0,
    this.shipping = 0.0,
    this.taxId,
    this.taxPercentage,
    this.taxAmount = 0.0,
    this.total = 0.0,
    this.currency = 'USD',
    required this.paymentMethod,
    this.paymentAddress,
    this.paymentAmount,
    this.paymentStatus = PaymentStatus.pending,
    this.shippingMethod,
    this.shippingName,
    this.shippingAddress,
    this.shippingPostal,
    this.shippingCountry,
    this.shippingPhone,
    this.statusHistory = const [],
    this.buyerNotes,
    this.sellerNotes,
    this.receiptNumber,
    this.receiptDate,
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

  /// Check if order is completed
  bool get isCompleted => status == OrderStatus.completed;

  /// Check if order is cancelled
  bool get isCancelled => status == OrderStatus.cancelled;

  /// Check if payment is completed
  bool get isPaymentCompleted => paymentStatus == PaymentStatus.completed;

  /// Get total item count
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  /// Export order as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('ORDER_ID: $orderId');
    buffer.writeln('BUYER_CALLSIGN: $buyerCallsign');
    buffer.writeln('BUYER_NPUB: $buyerNpub');
    buffer.writeln('SELLER_CALLSIGN: $sellerCallsign');
    buffer.writeln('SELLER_NPUB: $sellerNpub');
    buffer.writeln('CREATED: $created');
    buffer.writeln('STATUS: ${status.toFileString()}');
    buffer.writeln('BUYER_STATUS: ${buyerStatus.toFileString()}');
    buffer.writeln('SELLER_STATUS: ${sellerStatus.toFileString()}');
    buffer.writeln();

    // Order items
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

    // Pricing
    buffer.writeln('ITEMS_SUBTOTAL: ${itemsSubtotal.toStringAsFixed(2)}');
    buffer.writeln('PROMOTION_DISCOUNT: ${promotionDiscount.toStringAsFixed(2)}');
    buffer.writeln('COUPON_DISCOUNT: ${couponDiscount.toStringAsFixed(2)}');
    buffer.writeln('SUBTOTAL: ${subtotal.toStringAsFixed(2)}');
    buffer.writeln('SHIPPING: ${shipping.toStringAsFixed(2)}');
    if (taxId != null) {
      buffer.writeln('TAX_ID: $taxId');
    }
    if (taxPercentage != null) {
      buffer.writeln('TAX_PERCENTAGE: $taxPercentage');
    }
    buffer.writeln('TAX_AMOUNT: ${taxAmount.toStringAsFixed(2)}');
    buffer.writeln('TOTAL: ${total.toStringAsFixed(2)}');
    buffer.writeln('CURRENCY: $currency');
    buffer.writeln();

    // Payment information
    buffer.writeln('PAYMENT_METHOD: $paymentMethod');
    if (paymentAddress != null) {
      buffer.writeln('PAYMENT_ADDRESS: $paymentAddress');
    }
    if (paymentAmount != null) {
      buffer.writeln('PAYMENT_AMOUNT: ${paymentAmount!.toStringAsFixed(2)}');
    }
    buffer.writeln('PAYMENT_STATUS: ${paymentStatus.name}');
    buffer.writeln();

    // Shipping information
    if (shippingMethod != null) {
      buffer.writeln('SHIPPING_METHOD: $shippingMethod');
    }
    if (shippingName != null) {
      buffer.writeln('SHIPPING_NAME: $shippingName');
    }
    if (shippingAddress != null) {
      buffer.writeln('SHIPPING_ADDRESS: $shippingAddress');
    }
    if (shippingPostal != null) {
      buffer.writeln('SHIPPING_POSTAL: $shippingPostal');
    }
    if (shippingCountry != null) {
      buffer.writeln('SHIPPING_COUNTRY: $shippingCountry');
    }
    if (shippingPhone != null) {
      buffer.writeln('SHIPPING_PHONE: $shippingPhone');
    }
    if (shippingMethod != null) {
      buffer.writeln();
    }

    // Status history
    if (statusHistory.isNotEmpty) {
      buffer.writeln('STATUS_HISTORY:');
      for (var entry in statusHistory) {
        buffer.writeln(entry.toLine());
      }
      buffer.writeln();
    }

    // Buyer notes
    if (buyerNotes != null && buyerNotes!.isNotEmpty) {
      buffer.writeln('BUYER_NOTES:');
      buffer.writeln(buyerNotes);
      buffer.writeln();
    }

    // Seller notes
    if (sellerNotes != null && sellerNotes!.isNotEmpty) {
      buffer.writeln('SELLER_NOTES:');
      buffer.writeln(sellerNotes);
      buffer.writeln();
    }

    // Receipt info
    if (receiptNumber != null) {
      buffer.writeln('RECEIPT_NUMBER: $receiptNumber');
    }
    if (receiptDate != null) {
      buffer.writeln('RECEIPT_DATE: $receiptDate');
    }
    if (receiptNumber != null || receiptDate != null) {
      buffer.writeln();
    }

    // Additional metadata (excluding signatures which must be last)
    final regularMetadata = Map<String, String>.from(metadata);
    final buyerSig = regularMetadata.remove('buyer_signature');
    final sellerSig = regularMetadata.remove('seller_signature');

    for (var entry in regularMetadata.entries) {
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    // Signatures must be last if present
    if (buyerSig != null) {
      buffer.writeln('--> buyer_npub: $buyerNpub');
      buffer.writeln('--> buyer_signature: $buyerSig');
    }
    if (sellerSig != null) {
      buffer.writeln('--> seller_npub: $sellerNpub');
      buffer.writeln('--> seller_signature: $sellerSig');
    }

    return buffer.toString();
  }

  /// Parse order from file text
  static MarketOrder fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty order file');
    }

    String? orderId;
    String? buyerCallsign;
    String? buyerNpub;
    String? sellerCallsign;
    String? sellerNpub;
    String? created;
    OrderStatus status = OrderStatus.requested;
    BuyerStatus buyerStatus = BuyerStatus.awaitingConfirmation;
    SellerStatus sellerStatus = SellerStatus.reviewOrder;
    List<CartItem> items = [];
    List<AppliedPromotion> promotions = [];
    List<AppliedCoupon> coupons = [];
    double itemsSubtotal = 0.0;
    double promotionDiscount = 0.0;
    double couponDiscount = 0.0;
    double subtotal = 0.0;
    double shipping = 0.0;
    String? taxId;
    int? taxPercentage;
    double taxAmount = 0.0;
    double total = 0.0;
    String currency = 'USD';
    String? paymentMethod;
    String? paymentAddress;
    double? paymentAmount;
    PaymentStatus paymentStatus = PaymentStatus.pending;
    String? shippingMethod;
    String? shippingName;
    String? shippingAddress;
    String? shippingPostal;
    String? shippingCountry;
    String? shippingPhone;
    List<StatusHistoryEntry> statusHistory = [];
    String? buyerNotes;
    String? sellerNotes;
    String? receiptNumber;
    String? receiptDate;
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('ORDER_ID: ')) {
        orderId = line.substring(10).trim();
      } else if (line.startsWith('BUYER_CALLSIGN: ')) {
        buyerCallsign = line.substring(16).trim();
      } else if (line.startsWith('BUYER_NPUB: ')) {
        buyerNpub = line.substring(12).trim();
      } else if (line.startsWith('SELLER_CALLSIGN: ')) {
        sellerCallsign = line.substring(17).trim();
      } else if (line.startsWith('SELLER_NPUB: ')) {
        sellerNpub = line.substring(13).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = OrderStatus.fromString(line.substring(8).trim());
      } else if (line.startsWith('BUYER_STATUS: ')) {
        buyerStatus = BuyerStatus.fromString(line.substring(14).trim());
      } else if (line.startsWith('SELLER_STATUS: ')) {
        sellerStatus = SellerStatus.fromString(line.substring(15).trim());
      } else if (line == 'ITEMS:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          items.add(CartItem.fromLine(lines[i].substring(2)));
          i++;
        }
        continue;
      } else if (line == 'PROMOTIONS:') {
        i++;
        while (i < lines.length && lines[i].startsWith('- ')) {
          promotions.add(AppliedPromotion.fromLine(lines[i].substring(2)));
          i++;
        }
        continue;
      } else if (line == 'COUPONS:') {
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
      } else if (line.startsWith('SHIPPING: ')) {
        shipping = double.tryParse(line.substring(10).trim()) ?? 0.0;
      } else if (line.startsWith('TAX_ID: ')) {
        taxId = line.substring(8).trim();
      } else if (line.startsWith('TAX_PERCENTAGE: ')) {
        taxPercentage = int.tryParse(line.substring(16).trim());
      } else if (line.startsWith('TAX_AMOUNT: ')) {
        taxAmount = double.tryParse(line.substring(12).trim()) ?? 0.0;
      } else if (line.startsWith('TOTAL: ')) {
        total = double.tryParse(line.substring(7).trim()) ?? 0.0;
      } else if (line.startsWith('CURRENCY: ')) {
        currency = line.substring(10).trim();
      } else if (line.startsWith('PAYMENT_METHOD: ')) {
        paymentMethod = line.substring(16).trim();
      } else if (line.startsWith('PAYMENT_ADDRESS: ')) {
        paymentAddress = line.substring(17).trim();
      } else if (line.startsWith('PAYMENT_AMOUNT: ')) {
        paymentAmount = double.tryParse(line.substring(16).trim());
      } else if (line.startsWith('PAYMENT_STATUS: ')) {
        paymentStatus = PaymentStatus.fromString(line.substring(16).trim());
      } else if (line.startsWith('SHIPPING_METHOD: ')) {
        shippingMethod = line.substring(17).trim();
      } else if (line.startsWith('SHIPPING_NAME: ')) {
        shippingName = line.substring(15).trim();
      } else if (line.startsWith('SHIPPING_ADDRESS: ')) {
        shippingAddress = line.substring(18).trim();
      } else if (line.startsWith('SHIPPING_POSTAL: ')) {
        shippingPostal = line.substring(17).trim();
      } else if (line.startsWith('SHIPPING_COUNTRY: ')) {
        shippingCountry = line.substring(18).trim();
      } else if (line.startsWith('SHIPPING_PHONE: ')) {
        shippingPhone = line.substring(16).trim();
      } else if (line == 'STATUS_HISTORY:') {
        i++;
        while (i < lines.length && !lines[i].startsWith('BUYER_NOTES:') &&
               !lines[i].startsWith('SELLER_NOTES:') &&
               !lines[i].startsWith('RECEIPT_NUMBER:') &&
               !lines[i].startsWith('RECEIPT_DATE:') &&
               !lines[i].startsWith('-->') &&
               lines[i].trim().isNotEmpty) {
          statusHistory.add(StatusHistoryEntry.fromLine(lines[i]));
          i++;
        }
        continue;
      } else if (line == 'BUYER_NOTES:') {
        final notesLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('SELLER_NOTES:') &&
               !lines[i].startsWith('RECEIPT_NUMBER:') &&
               !lines[i].startsWith('RECEIPT_DATE:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            notesLines.add(lines[i]);
          }
          i++;
        }
        buyerNotes = notesLines.join('\n').trim();
        continue;
      } else if (line == 'SELLER_NOTES:') {
        final notesLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('RECEIPT_NUMBER:') &&
               !lines[i].startsWith('RECEIPT_DATE:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            notesLines.add(lines[i]);
          }
          i++;
        }
        sellerNotes = notesLines.join('\n').trim();
        continue;
      } else if (line.startsWith('RECEIPT_NUMBER: ')) {
        receiptNumber = line.substring(16).trim();
      } else if (line.startsWith('RECEIPT_DATE: ')) {
        receiptDate = line.substring(14).trim();
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
    if (orderId == null || buyerCallsign == null || buyerNpub == null ||
        sellerCallsign == null || sellerNpub == null || created == null ||
        paymentMethod == null) {
      throw Exception('Missing required order fields');
    }

    return MarketOrder(
      orderId: orderId,
      buyerCallsign: buyerCallsign,
      buyerNpub: buyerNpub,
      sellerCallsign: sellerCallsign,
      sellerNpub: sellerNpub,
      created: created,
      status: status,
      buyerStatus: buyerStatus,
      sellerStatus: sellerStatus,
      items: items,
      promotions: promotions,
      coupons: coupons,
      itemsSubtotal: itemsSubtotal,
      promotionDiscount: promotionDiscount,
      couponDiscount: couponDiscount,
      subtotal: subtotal,
      shipping: shipping,
      taxId: taxId,
      taxPercentage: taxPercentage,
      taxAmount: taxAmount,
      total: total,
      currency: currency,
      paymentMethod: paymentMethod,
      paymentAddress: paymentAddress,
      paymentAmount: paymentAmount,
      paymentStatus: paymentStatus,
      shippingMethod: shippingMethod,
      shippingName: shippingName,
      shippingAddress: shippingAddress,
      shippingPostal: shippingPostal,
      shippingCountry: shippingCountry,
      shippingPhone: shippingPhone,
      statusHistory: statusHistory,
      buyerNotes: buyerNotes,
      sellerNotes: sellerNotes,
      receiptNumber: receiptNumber,
      receiptDate: receiptDate,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketOrder copyWith({
    String? orderId,
    String? buyerCallsign,
    String? buyerNpub,
    String? sellerCallsign,
    String? sellerNpub,
    String? created,
    OrderStatus? status,
    BuyerStatus? buyerStatus,
    SellerStatus? sellerStatus,
    List<CartItem>? items,
    List<AppliedPromotion>? promotions,
    List<AppliedCoupon>? coupons,
    double? itemsSubtotal,
    double? promotionDiscount,
    double? couponDiscount,
    double? subtotal,
    double? shipping,
    String? taxId,
    int? taxPercentage,
    double? taxAmount,
    double? total,
    String? currency,
    String? paymentMethod,
    String? paymentAddress,
    double? paymentAmount,
    PaymentStatus? paymentStatus,
    String? shippingMethod,
    String? shippingName,
    String? shippingAddress,
    String? shippingPostal,
    String? shippingCountry,
    String? shippingPhone,
    List<StatusHistoryEntry>? statusHistory,
    String? buyerNotes,
    String? sellerNotes,
    String? receiptNumber,
    String? receiptDate,
    Map<String, String>? metadata,
  }) {
    return MarketOrder(
      orderId: orderId ?? this.orderId,
      buyerCallsign: buyerCallsign ?? this.buyerCallsign,
      buyerNpub: buyerNpub ?? this.buyerNpub,
      sellerCallsign: sellerCallsign ?? this.sellerCallsign,
      sellerNpub: sellerNpub ?? this.sellerNpub,
      created: created ?? this.created,
      status: status ?? this.status,
      buyerStatus: buyerStatus ?? this.buyerStatus,
      sellerStatus: sellerStatus ?? this.sellerStatus,
      items: items ?? this.items,
      promotions: promotions ?? this.promotions,
      coupons: coupons ?? this.coupons,
      itemsSubtotal: itemsSubtotal ?? this.itemsSubtotal,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      couponDiscount: couponDiscount ?? this.couponDiscount,
      subtotal: subtotal ?? this.subtotal,
      shipping: shipping ?? this.shipping,
      taxId: taxId ?? this.taxId,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentAddress: paymentAddress ?? this.paymentAddress,
      paymentAmount: paymentAmount ?? this.paymentAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      shippingMethod: shippingMethod ?? this.shippingMethod,
      shippingName: shippingName ?? this.shippingName,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      shippingPostal: shippingPostal ?? this.shippingPostal,
      shippingCountry: shippingCountry ?? this.shippingCountry,
      shippingPhone: shippingPhone ?? this.shippingPhone,
      statusHistory: statusHistory ?? this.statusHistory,
      buyerNotes: buyerNotes ?? this.buyerNotes,
      sellerNotes: sellerNotes ?? this.sellerNotes,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      receiptDate: receiptDate ?? this.receiptDate,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketOrder(id: $orderId, buyer: $buyerCallsign, seller: $sellerCallsign, status: ${status.toFileString()}, total: $currency ${total.toStringAsFixed(2)})';
  }
}
