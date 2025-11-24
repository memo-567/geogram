/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Shop status
enum ShopStatus {
  active,
  inactive,
  suspended;

  static ShopStatus fromString(String value) {
    return ShopStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => ShopStatus.active,
    );
  }
}

/// Model representing a marketplace shop
class MarketShop {
  final String shopName;
  final String shopOwner;
  final String ownerNpub;
  final String created;
  final ShopStatus status;
  final String? tagline;
  final String currency;
  final List<String> paymentMethods;
  final List<String> shippingOptions;
  final String? contactEmail;
  final String? contactPhone;
  final String? location;
  final List<String> languages;
  final Map<String, String> descriptions; // language -> description
  final Map<String, String> paymentInfo; // language -> payment info
  final Map<String, String> shippingInfo; // language -> shipping info
  final Map<String, String> returnPolicies; // language -> return policy
  final Map<String, String> metadata; // Additional metadata including npub/signature

  MarketShop({
    required this.shopName,
    required this.shopOwner,
    required this.ownerNpub,
    required this.created,
    this.status = ShopStatus.active,
    this.tagline,
    this.currency = 'USD',
    this.paymentMethods = const [],
    this.shippingOptions = const [],
    this.contactEmail,
    this.contactPhone,
    this.location,
    this.languages = const [],
    this.descriptions = const {},
    this.paymentInfo = const {},
    this.shippingInfo = const {},
    this.returnPolicies = const {},
    this.metadata = const {},
  });

  /// Parse timestamp to DateTime
  DateTime get dateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get NOSTR public key
  String? get npub => metadata['npub'];

  /// Get signature
  String? get signature => metadata['signature'];

  /// Check if shop is signed with NOSTR
  bool get isSigned => metadata.containsKey('signature');

  /// Check if shop is active
  bool get isActive => status == ShopStatus.active;

  /// Get description for a specific language with fallback
  String? getDescription(String lang) {
    return descriptions[lang.toUpperCase()] ??
           descriptions['EN'] ??
           descriptions.values.firstOrNull;
  }

  /// Get payment info for a specific language with fallback
  String? getPaymentInfo(String lang) {
    return paymentInfo[lang.toUpperCase()] ??
           paymentInfo['EN'] ??
           paymentInfo.values.firstOrNull;
  }

  /// Get shipping info for a specific language with fallback
  String? getShippingInfo(String lang) {
    return shippingInfo[lang.toUpperCase()] ??
           shippingInfo['EN'] ??
           shippingInfo.values.firstOrNull;
  }

  /// Get return policy for a specific language with fallback
  String? getReturnPolicy(String lang) {
    return returnPolicies[lang.toUpperCase()] ??
           returnPolicies['EN'] ??
           returnPolicies.values.firstOrNull;
  }

  /// Export shop as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('SHOP_NAME: $shopName');
    buffer.writeln('SHOP_OWNER: $shopOwner');
    buffer.writeln('OWNER_NPUB: $ownerNpub');
    buffer.writeln('CREATED: $created');
    buffer.writeln('STATUS: ${status.name}');

    // Optional fields
    if (tagline != null && tagline!.isNotEmpty) {
      buffer.writeln('TAGLINE: $tagline');
    }
    buffer.writeln('CURRENCY: $currency');

    if (paymentMethods.isNotEmpty) {
      buffer.writeln('PAYMENT_METHODS: ${paymentMethods.join(', ')}');
    }

    if (shippingOptions.isNotEmpty) {
      buffer.writeln('SHIPPING_OPTIONS: ${shippingOptions.join(', ')}');
    }

    if (contactEmail != null && contactEmail!.isNotEmpty) {
      buffer.writeln('CONTACT_EMAIL: $contactEmail');
    }

    if (contactPhone != null && contactPhone!.isNotEmpty) {
      buffer.writeln('CONTACT_PHONE: $contactPhone');
    }

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION: $location');
    }

    if (languages.isNotEmpty) {
      buffer.writeln('LANGUAGES: ${languages.join(', ')}');
    }

    buffer.writeln();

    // Multilanguage descriptions
    for (var entry in descriptions.entries) {
      buffer.writeln('# DESCRIPTION_${entry.key}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Payment info per language
    for (var entry in paymentInfo.entries) {
      buffer.writeln('PAYMENT_INFO_${entry.key}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Shipping info per language
    for (var entry in shippingInfo.entries) {
      buffer.writeln('SHIPPING_INFO_${entry.key}:');
      buffer.writeln(entry.value);
      buffer.writeln();
    }

    // Return policies per language
    for (var entry in returnPolicies.entries) {
      buffer.writeln('RETURN_POLICY_${entry.key}:');
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

  /// Parse shop from file text
  static MarketShop fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty shop file');
    }

    String? shopName;
    String? shopOwner;
    String? ownerNpub;
    String? created;
    ShopStatus status = ShopStatus.active;
    String? tagline;
    String currency = 'USD';
    List<String> paymentMethods = [];
    List<String> shippingOptions = [];
    String? contactEmail;
    String? contactPhone;
    String? location;
    List<String> languages = [];
    Map<String, String> descriptions = {};
    Map<String, String> paymentInfo = {};
    Map<String, String> shippingInfo = {};
    Map<String, String> returnPolicies = {};
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('SHOP_NAME: ')) {
        shopName = line.substring(11).trim();
      } else if (line.startsWith('SHOP_OWNER: ')) {
        shopOwner = line.substring(12).trim();
      } else if (line.startsWith('OWNER_NPUB: ')) {
        ownerNpub = line.substring(12).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('STATUS: ')) {
        status = ShopStatus.fromString(line.substring(8).trim());
      } else if (line.startsWith('TAGLINE: ')) {
        tagline = line.substring(9).trim();
      } else if (line.startsWith('CURRENCY: ')) {
        currency = line.substring(10).trim();
      } else if (line.startsWith('PAYMENT_METHODS: ')) {
        paymentMethods = line.substring(17).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else if (line.startsWith('SHIPPING_OPTIONS: ')) {
        shippingOptions = line.substring(18).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else if (line.startsWith('CONTACT_EMAIL: ')) {
        contactEmail = line.substring(15).trim();
      } else if (line.startsWith('CONTACT_PHONE: ')) {
        contactPhone = line.substring(15).trim();
      } else if (line.startsWith('LOCATION: ')) {
        location = line.substring(10).trim();
      } else if (line.startsWith('LANGUAGES: ')) {
        languages = line.substring(11).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else if (line.startsWith('# DESCRIPTION_')) {
        // Parse multilanguage description
        final lang = line.substring(14, line.indexOf(':')).trim();
        final descLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('# ') &&
               !lines[i].startsWith('PAYMENT_INFO_') &&
               !lines[i].startsWith('SHIPPING_INFO_') &&
               !lines[i].startsWith('RETURN_POLICY_') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            descLines.add(lines[i]);
          }
          i++;
        }
        descriptions[lang] = descLines.join('\n').trim();
        continue;
      } else if (line.startsWith('PAYMENT_INFO_')) {
        // Parse payment info
        final lang = line.substring(13, line.indexOf(':')).trim();
        final infoLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('# ') &&
               !lines[i].startsWith('PAYMENT_INFO_') &&
               !lines[i].startsWith('SHIPPING_INFO_') &&
               !lines[i].startsWith('RETURN_POLICY_') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            infoLines.add(lines[i]);
          }
          i++;
        }
        paymentInfo[lang] = infoLines.join('\n').trim();
        continue;
      } else if (line.startsWith('SHIPPING_INFO_')) {
        // Parse shipping info
        final lang = line.substring(14, line.indexOf(':')).trim();
        final infoLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('# ') &&
               !lines[i].startsWith('PAYMENT_INFO_') &&
               !lines[i].startsWith('SHIPPING_INFO_') &&
               !lines[i].startsWith('RETURN_POLICY_') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            infoLines.add(lines[i]);
          }
          i++;
        }
        shippingInfo[lang] = infoLines.join('\n').trim();
        continue;
      } else if (line.startsWith('RETURN_POLICY_')) {
        // Parse return policy
        final lang = line.substring(14, line.indexOf(':')).trim();
        final policyLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('# ') &&
               !lines[i].startsWith('PAYMENT_INFO_') &&
               !lines[i].startsWith('SHIPPING_INFO_') &&
               !lines[i].startsWith('RETURN_POLICY_') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            policyLines.add(lines[i]);
          }
          i++;
        }
        returnPolicies[lang] = policyLines.join('\n').trim();
        continue;
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
    if (shopName == null || shopOwner == null || ownerNpub == null || created == null) {
      throw Exception('Missing required shop fields');
    }

    return MarketShop(
      shopName: shopName,
      shopOwner: shopOwner,
      ownerNpub: ownerNpub,
      created: created,
      status: status,
      tagline: tagline,
      currency: currency,
      paymentMethods: paymentMethods,
      shippingOptions: shippingOptions,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      location: location,
      languages: languages,
      descriptions: descriptions,
      paymentInfo: paymentInfo,
      shippingInfo: shippingInfo,
      returnPolicies: returnPolicies,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketShop copyWith({
    String? shopName,
    String? shopOwner,
    String? ownerNpub,
    String? created,
    ShopStatus? status,
    String? tagline,
    String? currency,
    List<String>? paymentMethods,
    List<String>? shippingOptions,
    String? contactEmail,
    String? contactPhone,
    String? location,
    List<String>? languages,
    Map<String, String>? descriptions,
    Map<String, String>? paymentInfo,
    Map<String, String>? shippingInfo,
    Map<String, String>? returnPolicies,
    Map<String, String>? metadata,
  }) {
    return MarketShop(
      shopName: shopName ?? this.shopName,
      shopOwner: shopOwner ?? this.shopOwner,
      ownerNpub: ownerNpub ?? this.ownerNpub,
      created: created ?? this.created,
      status: status ?? this.status,
      tagline: tagline ?? this.tagline,
      currency: currency ?? this.currency,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      shippingOptions: shippingOptions ?? this.shippingOptions,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      location: location ?? this.location,
      languages: languages ?? this.languages,
      descriptions: descriptions ?? this.descriptions,
      paymentInfo: paymentInfo ?? this.paymentInfo,
      shippingInfo: shippingInfo ?? this.shippingInfo,
      returnPolicies: returnPolicies ?? this.returnPolicies,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketShop(name: $shopName, owner: $shopOwner, status: ${status.name})';
  }
}
