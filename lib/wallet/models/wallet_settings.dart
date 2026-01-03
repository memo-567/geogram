/// Wallet settings model for user preferences.
///
/// Stores default settings for debt creation including
/// jurisdiction and payment terms.
library;

import '../../services/config_service.dart';
import '../../services/location_service.dart';

// Re-export JurisdictionInfo for convenience
export '../../services/location_service.dart' show JurisdictionInfo;

/// User preferences for wallet operations.
class WalletSettings {
  /// Default jurisdiction for debt contracts.
  /// This determines the governing law for disputes.
  String? defaultJurisdiction;

  /// ISO2 country code (e.g., 'US', 'PT', 'DE')
  String? defaultCountryCode;

  /// Default currency code (e.g., 'EUR', 'USD')
  String defaultCurrency;

  /// Whether to include standard legal terms by default
  bool includeTermsByDefault;

  /// Default interest rate (annual percentage, e.g., 5.0 for 5%)
  double? defaultInterestRate;

  /// Default payment frequency for installments
  PaymentFrequency defaultPaymentFrequency;

  /// Whether to auto-detect jurisdiction from location
  bool autoDetectJurisdiction;

  /// Custom terms to include by default in new debts
  String? defaultCustomTerms;

  /// Whether to include custom terms by default
  bool includeCustomTermsByDefault;

  WalletSettings({
    this.defaultJurisdiction,
    this.defaultCountryCode,
    this.defaultCurrency = 'EUR',
    this.includeTermsByDefault = true,
    this.defaultInterestRate,
    this.defaultPaymentFrequency = PaymentFrequency.monthly,
    this.autoDetectJurisdiction = true,
    this.defaultCustomTerms,
    this.includeCustomTermsByDefault = false,
  });

  /// Create settings from JSON map.
  factory WalletSettings.fromJson(Map<String, dynamic> json) {
    return WalletSettings(
      defaultJurisdiction: json['defaultJurisdiction'] as String?,
      defaultCountryCode: json['defaultCountryCode'] as String?,
      defaultCurrency: json['defaultCurrency'] as String? ?? 'EUR',
      includeTermsByDefault: json['includeTermsByDefault'] as bool? ?? true,
      defaultInterestRate: (json['defaultInterestRate'] as num?)?.toDouble(),
      defaultPaymentFrequency: PaymentFrequency.fromString(
        json['defaultPaymentFrequency'] as String?,
      ),
      autoDetectJurisdiction: json['autoDetectJurisdiction'] as bool? ?? true,
      defaultCustomTerms: json['defaultCustomTerms'] as String?,
      includeCustomTermsByDefault: json['includeCustomTermsByDefault'] as bool? ?? false,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'defaultJurisdiction': defaultJurisdiction,
      'defaultCountryCode': defaultCountryCode,
      'defaultCurrency': defaultCurrency,
      'includeTermsByDefault': includeTermsByDefault,
      'defaultInterestRate': defaultInterestRate,
      'defaultPaymentFrequency': defaultPaymentFrequency.name,
      'autoDetectJurisdiction': autoDetectJurisdiction,
      'defaultCustomTerms': defaultCustomTerms,
      'includeCustomTermsByDefault': includeCustomTermsByDefault,
    };
  }

  /// Create a copy with modified fields.
  WalletSettings copyWith({
    String? defaultJurisdiction,
    String? defaultCountryCode,
    String? defaultCurrency,
    bool? includeTermsByDefault,
    double? defaultInterestRate,
    PaymentFrequency? defaultPaymentFrequency,
    bool? autoDetectJurisdiction,
    String? defaultCustomTerms,
    bool clearCustomTerms = false,
    bool? includeCustomTermsByDefault,
  }) {
    return WalletSettings(
      defaultJurisdiction: defaultJurisdiction ?? this.defaultJurisdiction,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      includeTermsByDefault:
          includeTermsByDefault ?? this.includeTermsByDefault,
      defaultInterestRate: defaultInterestRate ?? this.defaultInterestRate,
      defaultPaymentFrequency:
          defaultPaymentFrequency ?? this.defaultPaymentFrequency,
      autoDetectJurisdiction:
          autoDetectJurisdiction ?? this.autoDetectJurisdiction,
      defaultCustomTerms:
          clearCustomTerms ? null : (defaultCustomTerms ?? this.defaultCustomTerms),
      includeCustomTermsByDefault:
          includeCustomTermsByDefault ?? this.includeCustomTermsByDefault,
    );
  }

  /// Detect jurisdiction from coordinates using worldcities database.
  /// Delegates to LocationService.detectJurisdiction for centralized handling.
  static Future<JurisdictionInfo?> detectJurisdiction(
    double latitude,
    double longitude,
  ) async {
    final locationService = LocationService();
    return locationService.detectJurisdiction(latitude, longitude);
  }

  /// Load settings from ConfigService.
  static Future<WalletSettings> load() async {
    final config = ConfigService();
    final json = config.getNestedValue('settings.wallet', <String, dynamic>{});
    if (json is Map<String, dynamic>) {
      return WalletSettings.fromJson(json);
    }
    return WalletSettings();
  }

  /// Save settings to ConfigService.
  Future<void> save() async {
    final config = ConfigService();
    config.setNestedValue('settings.wallet', toJson());
  }
}

/// Payment frequency options for installment plans.
enum PaymentFrequency {
  weekly,
  biweekly,
  monthly,
  quarterly,
  yearly,
  custom;

  /// Get the number of days between payments.
  int get daysInterval {
    switch (this) {
      case PaymentFrequency.weekly:
        return 7;
      case PaymentFrequency.biweekly:
        return 14;
      case PaymentFrequency.monthly:
        return 30;
      case PaymentFrequency.quarterly:
        return 91;
      case PaymentFrequency.yearly:
        return 365;
      case PaymentFrequency.custom:
        return 30; // Default for custom
    }
  }

  /// Parse from string.
  static PaymentFrequency fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'weekly':
        return PaymentFrequency.weekly;
      case 'biweekly':
        return PaymentFrequency.biweekly;
      case 'monthly':
        return PaymentFrequency.monthly;
      case 'quarterly':
        return PaymentFrequency.quarterly;
      case 'yearly':
        return PaymentFrequency.yearly;
      case 'custom':
        return PaymentFrequency.custom;
      default:
        return PaymentFrequency.monthly;
    }
  }

  /// Human-readable name.
  String get displayName {
    switch (this) {
      case PaymentFrequency.weekly:
        return 'Weekly';
      case PaymentFrequency.biweekly:
        return 'Bi-weekly';
      case PaymentFrequency.monthly:
        return 'Monthly';
      case PaymentFrequency.quarterly:
        return 'Quarterly';
      case PaymentFrequency.yearly:
        return 'Yearly';
      case PaymentFrequency.custom:
        return 'Custom';
    }
  }
}
