/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/market_shop.dart';
import '../models/market_item.dart';
import '../models/market_cart.dart';
import '../models/market_order.dart';
import '../models/market_review.dart';
import '../models/market_promotion.dart';
import '../models/market_coupon.dart';
import 'log_service.dart';
import 'profile_storage.dart';

/// Service for managing marketplace operations
class MarketService {
  static final MarketService _instance = MarketService._internal();
  factory MarketService() => _instance;
  MarketService._internal();

  /// Profile storage for file operations (encrypted or filesystem)
  /// IMPORTANT: This MUST be set before using the service.
  late ProfileStorage _storage;

  String? _collectionPath;
  MarketShop? _shop;

  /// Whether using encrypted storage
  bool get useEncryptedStorage => _storage.isEncrypted;

  /// Set the profile storage for file operations
  /// MUST be called before initializeCollection
  void setStorage(ProfileStorage storage) {
    _storage = storage;
  }

  /// Initialize market service for a collection
  Future<void> initializeCollection(String collectionPath, {String? creatorNpub}) async {
    LogService().log('MarketService: Initializing with collection path: $collectionPath');
    _collectionPath = collectionPath;

    // Ensure shop directory exists using storage
    await _storage.createDirectory('shop');
    LogService().log('MarketService: Created shop directory');

    // Load shop
    await _loadShop();

    // If shop doesn't exist and creator provided, initialize new shop
    if (_shop == null && creatorNpub != null && creatorNpub.isNotEmpty) {
      LogService().log('MarketService: Creating new shop for creator: $creatorNpub');
      // Shop will be created when user fills in shop details
    }
  }

  /// Load shop from file
  Future<void> _loadShop() async {
    if (_collectionPath == null) return;

    final content = await _storage.readString('shop/shop.txt');
    if (content != null) {
      try {
        _shop = MarketShop.fromText(content);
        LogService().log('MarketService: Loaded shop: ${_shop!.shopName}');
      } catch (e) {
        LogService().log('MarketService: Error loading shop: $e');
        _shop = null;
      }
    } else {
      _shop = null;
    }
  }

  /// Get current shop
  MarketShop? getShop() => _shop;

  /// Save shop
  Future<void> saveShop(MarketShop shop) async {
    if (_collectionPath == null) return;

    _shop = shop;

    await _storage.writeString('shop/shop.txt', shop.exportAsText());

    LogService().log('MarketService: Saved shop: ${shop.shopName}');
  }

  // ============================================================================
  // ITEMS
  // ============================================================================

  /// Get all item categories (from folder structure)
  Future<List<String>> getCategories() async {
    if (_collectionPath == null) return [];

    if (!await _storage.exists('shop/items')) return [];

    final categories = <String>[];
    await _collectCategoriesFromStorage('shop/items', '', categories);

    categories.sort();
    return categories;
  }

  /// Recursively collect categories from storage
  Future<void> _collectCategoriesFromStorage(String basePath, String relativePath, List<String> categories) async {
    final currentPath = relativePath.isEmpty ? basePath : '$basePath/$relativePath';
    final entries = await _storage.listDirectory(currentPath);

    for (var entry in entries) {
      if (entry.isDirectory) {
        // Skip item directories (they start with "item-")
        if (!entry.name.startsWith('item-')) {
          final categoryPath = relativePath.isEmpty ? entry.name : '$relativePath/${entry.name}';
          categories.add(categoryPath);
          await _collectCategoriesFromStorage(basePath, categoryPath, categories);
        }
      }
    }
  }

  /// Load all items
  Future<List<MarketItem>> loadItems({String? category}) async {
    if (_collectionPath == null) return [];

    if (!await _storage.exists('shop/items')) return [];

    final items = <MarketItem>[];

    // If category specified, search within that category folder
    final searchPath = category != null ? 'shop/items/$category' : 'shop/items';

    if (!await _storage.exists(searchPath)) return [];

    await _loadItemsFromStorage(searchPath, items);

    // Sort by updated date (most recent first)
    items.sort((a, b) => b.updatedDate.compareTo(a.updatedDate));

    return items;
  }

  /// Recursively load items from storage
  Future<void> _loadItemsFromStorage(String path, List<MarketItem> items) async {
    final entries = await _storage.listDirectory(path);

    for (var entry in entries) {
      if (entry.isDirectory) {
        // Check if this is an item directory (contains item.txt)
        final itemFilePath = '${entry.path}/item.txt';
        final content = await _storage.readString(itemFilePath);
        if (content != null) {
          try {
            final itemId = entry.name;
            // Get category path (relative to shop/items/)
            String? categoryPath;
            final relativePath = entry.path.replaceFirst('shop/items/', '');
            final parts = relativePath.split('/');
            if (parts.length > 1) {
              categoryPath = parts.sublist(0, parts.length - 1).join('/');
            }

            final item = MarketItem.fromText(content, itemId, categoryPath: categoryPath);
            items.add(item);
          } catch (e) {
            LogService().log('MarketService: Error loading item from ${entry.path}: $e');
          }
        } else {
          // Not an item directory, recurse into it
          await _loadItemsFromStorage(entry.path, items);
        }
      }
    }
  }

  /// Load single item
  Future<MarketItem?> loadItem(String itemId, {String? categoryPath}) async {
    if (_collectionPath == null) return null;

    // Search for item in all categories if not specified
    if (categoryPath == null) {
      final allItems = await loadItems();
      try {
        return allItems.firstWhere((item) => item.itemId == itemId);
      } catch (e) {
        return null;
      }
    }

    final itemFilePath = 'shop/items/$categoryPath/$itemId/item.txt';
    final content = await _storage.readString(itemFilePath);
    if (content == null) return null;

    try {
      return MarketItem.fromText(content, itemId, categoryPath: categoryPath);
    } catch (e) {
      LogService().log('MarketService: Error loading item $itemId: $e');
      return null;
    }
  }

  /// Save item
  Future<void> saveItem(MarketItem item) async {
    if (_collectionPath == null) return;

    final categoryPath = item.categoryPath ?? 'uncategorized';
    final itemDirPath = 'shop/items/$categoryPath/${item.itemId}';

    await _storage.createDirectory(itemDirPath);
    await _storage.writeString('$itemDirPath/item.txt', item.exportAsText());

    LogService().log('MarketService: Saved item: ${item.itemId}');
  }

  /// Delete item
  Future<void> deleteItem(String itemId, {String? categoryPath}) async {
    if (_collectionPath == null) return;

    if (categoryPath == null) {
      // Find item in all categories
      final allItems = await loadItems();
      final item = allItems.firstWhere(
        (i) => i.itemId == itemId,
        orElse: () => throw Exception('Item not found'),
      );
      categoryPath = item.categoryPath ?? 'uncategorized';
    }

    final itemDirPath = 'shop/items/$categoryPath/$itemId';
    if (await _storage.exists(itemDirPath)) {
      await _storage.deleteDirectory(itemDirPath, recursive: true);
      LogService().log('MarketService: Deleted item: $itemId');
    }
  }

  // ============================================================================
  // REVIEWS
  // ============================================================================

  /// Load reviews for an item
  Future<List<MarketReview>> loadReviews(String itemId, {String? categoryPath}) async {
    if (_collectionPath == null) return [];

    if (categoryPath == null) {
      final allItems = await loadItems();
      final item = allItems.firstWhere(
        (i) => i.itemId == itemId,
        orElse: () => throw Exception('Item not found'),
      );
      categoryPath = item.categoryPath ?? 'uncategorized';
    }

    final reviewsPath = 'shop/items/$categoryPath/$itemId/reviews';
    if (!await _storage.exists(reviewsPath)) return [];

    final reviews = <MarketReview>[];
    final entries = await _storage.listDirectory(reviewsPath);

    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.txt')) {
        try {
          final content = await _storage.readString(entry.path);
          if (content != null) {
            final review = MarketReview.fromText(content);
            reviews.add(review);
          }
        } catch (e) {
          LogService().log('MarketService: Error loading review from ${entry.path}: $e');
        }
      }
    }

    // Sort by created date (most recent first)
    reviews.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return reviews;
  }

  /// Save review
  Future<void> saveReview(MarketReview review, {String? categoryPath}) async {
    if (_collectionPath == null) return;

    if (categoryPath == null) {
      final allItems = await loadItems();
      final item = allItems.firstWhere(
        (i) => i.itemId == review.itemId,
        orElse: () => throw Exception('Item not found'),
      );
      categoryPath = item.categoryPath ?? 'uncategorized';
    }

    final reviewsPath = 'shop/items/$categoryPath/${review.itemId}/reviews';
    await _storage.createDirectory(reviewsPath);
    await _storage.writeString('$reviewsPath/review-${review.reviewer}.txt', review.exportAsText());

    LogService().log('MarketService: Saved review for item ${review.itemId}');
  }

  // ============================================================================
  // CARTS
  // ============================================================================

  /// Load cart for buyer
  Future<MarketCart?> loadCart(String buyerCallsign) async {
    if (_collectionPath == null) return null;

    if (!await _storage.exists('carts')) return null;

    // Find cart file for buyer
    final entries = await _storage.listDirectory('carts');
    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.contains('cart-$buyerCallsign')) {
        try {
          final content = await _storage.readString(entry.path);
          if (content != null) {
            return MarketCart.fromText(content);
          }
        } catch (e) {
          LogService().log('MarketService: Error loading cart: $e');
          return null;
        }
      }
    }

    return null;
  }

  /// Save cart
  Future<void> saveCart(MarketCart cart) async {
    if (_collectionPath == null) return;

    await _storage.createDirectory('carts');
    await _storage.writeString('carts/${cart.cartId}.txt', cart.exportAsText());

    LogService().log('MarketService: Saved cart: ${cart.cartId}');
  }

  // ============================================================================
  // ORDERS
  // ============================================================================

  /// Load all orders
  Future<List<MarketOrder>> loadOrders({int? year}) async {
    if (_collectionPath == null) return [];

    if (!await _storage.exists('orders')) return [];

    final orders = <MarketOrder>[];

    if (year != null) {
      // Load orders from specific year
      if (await _storage.exists('orders/$year')) {
        await _loadOrdersFromStorage('orders/$year', orders);
      }
    } else {
      // Load orders from all years
      final entries = await _storage.listDirectory('orders');
      for (var entry in entries) {
        if (entry.isDirectory) {
          await _loadOrdersFromStorage(entry.path, orders);
        }
      }
    }

    // Sort by created date (most recent first)
    orders.sort((a, b) => b.createdDate.compareTo(a.createdDate));

    return orders;
  }

  Future<void> _loadOrdersFromStorage(String path, List<MarketOrder> orders) async {
    final entries = await _storage.listDirectory(path);
    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.txt')) {
        try {
          final content = await _storage.readString(entry.path);
          if (content != null) {
            final order = MarketOrder.fromText(content);
            orders.add(order);
          }
        } catch (e) {
          LogService().log('MarketService: Error loading order from ${entry.path}: $e');
        }
      }
    }
  }

  /// Load single order
  Future<MarketOrder?> loadOrder(String orderId) async {
    final orders = await loadOrders();
    try {
      return orders.firstWhere((o) => o.orderId == orderId);
    } catch (e) {
      return null;
    }
  }

  /// Save order
  Future<void> saveOrder(MarketOrder order) async {
    if (_collectionPath == null) return;

    final year = order.createdDate.year;
    final yearPath = 'orders/$year';

    await _storage.createDirectory(yearPath);
    await _storage.writeString('$yearPath/${order.orderId}.txt', order.exportAsText());

    LogService().log('MarketService: Saved order: ${order.orderId}');
  }

  // ============================================================================
  // PROMOTIONS
  // ============================================================================

  /// Load all promotions
  Future<List<MarketPromotion>> loadPromotions() async {
    if (_collectionPath == null) return [];

    if (!await _storage.exists('shop/promotions')) return [];

    final promotions = <MarketPromotion>[];

    final entries = await _storage.listDirectory('shop/promotions');
    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.txt')) {
        try {
          final content = await _storage.readString(entry.path);
          if (content != null) {
            final promo = MarketPromotion.fromText(content);
            promotions.add(promo);
          }
        } catch (e) {
          LogService().log('MarketService: Error loading promotion from ${entry.path}: $e');
        }
      }
    }

    // Sort by start date (most recent first)
    promotions.sort((a, b) => b.startDateTime.compareTo(a.startDateTime));

    return promotions;
  }

  /// Get active promotions
  Future<List<MarketPromotion>> getActivePromotions() async {
    final allPromos = await loadPromotions();
    return allPromos.where((p) => p.isCurrentlyActive).toList();
  }

  /// Save promotion
  Future<void> savePromotion(MarketPromotion promotion) async {
    if (_collectionPath == null) return;

    await _storage.createDirectory('shop/promotions');
    await _storage.writeString('shop/promotions/${promotion.promoId}.txt', promotion.exportAsText());

    LogService().log('MarketService: Saved promotion: ${promotion.promoId}');
  }

  // ============================================================================
  // COUPONS
  // ============================================================================

  /// Load all coupons
  Future<List<MarketCoupon>> loadCoupons() async {
    if (_collectionPath == null) return [];

    if (!await _storage.exists('coupons')) return [];

    final coupons = <MarketCoupon>[];

    final entries = await _storage.listDirectory('coupons');
    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.endsWith('.txt')) {
        try {
          final content = await _storage.readString(entry.path);
          if (content != null) {
            final coupon = MarketCoupon.fromText(content);
            coupons.add(coupon);
          }
        } catch (e) {
          LogService().log('MarketService: Error loading coupon from ${entry.path}: $e');
        }
      }
    }

    return coupons;
  }

  /// Get valid coupons
  Future<List<MarketCoupon>> getValidCoupons() async {
    final allCoupons = await loadCoupons();
    return allCoupons.where((c) => c.isValid).toList();
  }

  /// Validate coupon code
  Future<MarketCoupon?> validateCoupon(String code, String userNpub) async {
    final coupons = await loadCoupons();
    try {
      final coupon = coupons.firstWhere((c) => c.couponCode.toUpperCase() == code.toUpperCase());
      if (coupon.isValid && coupon.canUserUse(userNpub)) {
        return coupon;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Save coupon
  Future<void> saveCoupon(MarketCoupon coupon) async {
    if (_collectionPath == null) return;

    await _storage.createDirectory('coupons');
    await _storage.writeString('coupons/coupon-${coupon.couponCode}.txt', coupon.exportAsText());

    LogService().log('MarketService: Saved coupon: ${coupon.couponCode}');
  }

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  /// Generate unique item ID based on content hash
  String generateItemId(String content) {
    final bytes = utf8.encode(content);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 6);
  }

  /// Generate unique order ID based on content hash
  String generateOrderId(String content) {
    final bytes = utf8.encode(content);
    final hash = sha256.convert(bytes);
    final date = DateTime.now();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return 'order-${dateStr}_${hash.toString().substring(0, 6)}';
  }

  /// Generate unique cart ID based on buyer and timestamp
  String generateCartId(String buyerCallsign) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode('$buyerCallsign-$timestamp');
    final hash = sha256.convert(bytes);
    return 'cart-${buyerCallsign}_${hash.toString().substring(0, 6)}';
  }

  /// Get timestamp in Geogram format (YYYY-MM-DD HH:MM_ss)
  String getTimestamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
           '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_'
           '${now.second.toString().padLeft(2, '0')}';
  }
}
