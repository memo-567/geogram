/// Currency definitions and time formatting for the Wallet app.
///
/// Supports major world currencies (EUR, USD prioritized), cryptocurrencies,
/// custom currencies, and time measured in minutes with human-readable formatting.
library;

import 'dart:convert';

import '../../services/config_service.dart';

/// Represents a currency with its code, name, and symbol.
class Currency {
  final String code;
  final String name;
  final String symbol;
  final bool isTime;
  final bool isCrypto;
  final bool isCustom;
  final int decimals;

  const Currency({
    required this.code,
    required this.name,
    required this.symbol,
    this.isTime = false,
    this.isCrypto = false,
    this.isCustom = false,
    this.decimals = 2,
  });

  /// Create a custom currency.
  factory Currency.custom({
    required String code,
    required String name,
    String? symbol,
    int decimals = 2,
  }) {
    return Currency(
      code: code.toUpperCase(),
      name: name,
      symbol: symbol ?? '${code.toUpperCase()} ',
      isCustom: true,
      decimals: decimals,
    );
  }

  /// Format an amount with the currency symbol.
  String format(double amount) {
    if (isTime) {
      return formatTimeAmount(amount, code);
    }
    // Handle currencies with no decimal places
    if (decimals == 0) {
      return '$symbol${amount.toInt()}';
    }
    // Crypto typically shows more decimals for small amounts
    if (isCrypto && amount < 1 && amount > 0) {
      // Show up to 8 decimals for small crypto amounts, trim trailing zeros
      final formatted = amount.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return '$symbol$formatted';
    }
    return '$symbol${amount.toStringAsFixed(decimals)}';
  }

  /// Convert to JSON for persistence (custom currencies).
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'symbol': symbol,
      'isTime': isTime,
      'isCrypto': isCrypto,
      'isCustom': isCustom,
      'decimals': decimals,
    };
  }

  /// Create from JSON.
  factory Currency.fromJson(Map<String, dynamic> json) {
    return Currency(
      code: json['code'] as String,
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      isTime: json['isTime'] as bool? ?? false,
      isCrypto: json['isCrypto'] as bool? ?? false,
      isCustom: json['isCustom'] as bool? ?? false,
      decimals: json['decimals'] as int? ?? 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Currency && runtimeType == other.runtimeType && code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$code ($name)';
}

/// All supported currencies, ordered by priority.
class Currencies {
  Currencies._();

  static const _customCurrenciesKey = 'wallet_custom_currencies';

  // Time currencies
  static const min = Currency(
    code: 'MIN',
    name: 'Minutes',
    symbol: '',
    isTime: true,
  );
  static const hour = Currency(
    code: 'HOUR',
    name: 'Hours',
    symbol: '',
    isTime: true,
  );
  static const day = Currency(
    code: 'DAY',
    name: 'Days',
    symbol: '',
    isTime: true,
  );
  static const week = Currency(
    code: 'WEEK',
    name: 'Weeks',
    symbol: '',
    isTime: true,
  );
  static const month = Currency(
    code: 'MONTH',
    name: 'Months',
    symbol: '',
    isTime: true,
  );

  // Cryptocurrencies (prioritized order - privacy coins first)
  static const xmr = Currency(
    code: 'XMR',
    name: 'Monero',
    symbol: 'XMR ',
    isCrypto: true,
    decimals: 8,
  );
  static const btc = Currency(
    code: 'BTC',
    name: 'Bitcoin',
    symbol: '₿',
    isCrypto: true,
    decimals: 8,
  );
  static const ltc = Currency(
    code: 'LTC',
    name: 'Litecoin',
    symbol: 'Ł',
    isCrypto: true,
    decimals: 8,
  );
  static const bnb = Currency(
    code: 'BNB',
    name: 'BNB',
    symbol: 'BNB ',
    isCrypto: true,
    decimals: 8,
  );
  static const eth = Currency(
    code: 'ETH',
    name: 'Ethereum',
    symbol: 'Ξ',
    isCrypto: true,
    decimals: 8,
  );
  static const beam = Currency(
    code: 'BEAM',
    name: 'Beam',
    symbol: 'BEAM ',
    isCrypto: true,
    decimals: 8,
  );
  static const signa = Currency(
    code: 'SIGNA',
    name: 'Signum',
    symbol: 'SIGNA ',
    isCrypto: true,
    decimals: 8,
  );
  static const wow = Currency(
    code: 'WOW',
    name: 'Wownero',
    symbol: 'WOW ',
    isCrypto: true,
    decimals: 8,
  );
  static const xrp = Currency(
    code: 'XRP',
    name: 'XRP',
    symbol: 'XRP ',
    isCrypto: true,
    decimals: 6,
  );
  static const ada = Currency(
    code: 'ADA',
    name: 'Cardano',
    symbol: '₳',
    isCrypto: true,
    decimals: 6,
  );
  static const sol = Currency(
    code: 'SOL',
    name: 'Solana',
    symbol: 'SOL ',
    isCrypto: true,
    decimals: 9,
  );
  static const doge = Currency(
    code: 'DOGE',
    name: 'Dogecoin',
    symbol: 'Ð',
    isCrypto: true,
    decimals: 8,
  );
  static const dot = Currency(
    code: 'DOT',
    name: 'Polkadot',
    symbol: 'DOT ',
    isCrypto: true,
    decimals: 10,
  );
  static const matic = Currency(
    code: 'MATIC',
    name: 'Polygon',
    symbol: 'MATIC ',
    isCrypto: true,
    decimals: 8,
  );
  static const avax = Currency(
    code: 'AVAX',
    name: 'Avalanche',
    symbol: 'AVAX ',
    isCrypto: true,
    decimals: 9,
  );
  static const atom = Currency(
    code: 'ATOM',
    name: 'Cosmos',
    symbol: 'ATOM ',
    isCrypto: true,
    decimals: 6,
  );
  static const link = Currency(
    code: 'LINK',
    name: 'Chainlink',
    symbol: 'LINK ',
    isCrypto: true,
    decimals: 8,
  );
  static const usdt = Currency(
    code: 'USDT',
    name: 'Tether',
    symbol: 'USDT ',
    isCrypto: true,
    decimals: 6,
  );
  static const usdc = Currency(
    code: 'USDC',
    name: 'USD Coin',
    symbol: 'USDC ',
    isCrypto: true,
    decimals: 6,
  );

  // Monetary currencies (prioritized order)
  static const eur = Currency(code: 'EUR', name: 'Euro', symbol: '€');
  static const usd = Currency(code: 'USD', name: 'US Dollar', symbol: '\$');
  static const gbp = Currency(code: 'GBP', name: 'British Pound', symbol: '£');
  static const chf = Currency(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF ');
  static const jpy = Currency(code: 'JPY', name: 'Japanese Yen', symbol: '¥', decimals: 0);
  static const cny = Currency(code: 'CNY', name: 'Chinese Yuan', symbol: '¥');
  static const cad = Currency(code: 'CAD', name: 'Canadian Dollar', symbol: 'C\$');
  static const aud = Currency(code: 'AUD', name: 'Australian Dollar', symbol: 'A\$');
  static const brl = Currency(code: 'BRL', name: 'Brazilian Real', symbol: 'R\$');
  static const mxn = Currency(code: 'MXN', name: 'Mexican Peso', symbol: 'MX\$');
  static const inr = Currency(code: 'INR', name: 'Indian Rupee', symbol: '₹');
  static const rub = Currency(code: 'RUB', name: 'Russian Ruble', symbol: '₽');
  static const krw = Currency(code: 'KRW', name: 'South Korean Won', symbol: '₩', decimals: 0);
  static const sek = Currency(code: 'SEK', name: 'Swedish Krona', symbol: 'kr ');
  static const nok = Currency(code: 'NOK', name: 'Norwegian Krone', symbol: 'kr ');
  static const dkk = Currency(code: 'DKK', name: 'Danish Krone', symbol: 'kr ');
  static const pln = Currency(code: 'PLN', name: 'Polish Zloty', symbol: 'zł');
  static const czk = Currency(code: 'CZK', name: 'Czech Koruna', symbol: 'Kč ');
  static const huf = Currency(code: 'HUF', name: 'Hungarian Forint', symbol: 'Ft ', decimals: 0);
  static const try_ = Currency(code: 'TRY', name: 'Turkish Lira', symbol: '₺');

  /// Built-in currencies in priority order.
  static const List<Currency> builtIn = [
    // Time (from smallest to largest unit)
    min,
    hour,
    day,
    week,
    month,
    // Crypto (privacy-focused first)
    xmr,
    btc,
    ltc,
    bnb,
    eth,
    beam,
    signa,
    wow,
    xrp,
    ada,
    sol,
    doge,
    dot,
    matic,
    avax,
    atom,
    link,
    usdt,
    usdc,
    // Fiat
    eur,
    usd,
    gbp,
    chf,
    jpy,
    cny,
    cad,
    aud,
    brl,
    mxn,
    inr,
    rub,
    krw,
    sek,
    nok,
    dkk,
    pln,
    czk,
    huf,
    try_,
  ];

  /// Custom currencies added by the user.
  static List<Currency> _customCurrencies = [];

  /// All currencies (built-in + custom).
  static List<Currency> get all => [...builtIn, ..._customCurrencies];

  /// Cryptocurrency currencies only.
  static List<Currency> get crypto => builtIn.where((c) => c.isCrypto).toList();

  /// Fiat monetary currencies only (excludes time and crypto).
  static List<Currency> get fiat => builtIn.where((c) => !c.isTime && !c.isCrypto).toList();

  /// Monetary currencies only (excludes time, includes crypto).
  static List<Currency> get monetary => all.where((c) => !c.isTime).toList();

  /// Custom currencies only.
  static List<Currency> get custom => List.unmodifiable(_customCurrencies);

  /// Load custom currencies from storage.
  static Future<void> loadCustomCurrencies() async {
    final config = ConfigService();
    final jsonList = config.get(_customCurrenciesKey) as List<dynamic>?;
    if (jsonList != null) {
      _customCurrencies = jsonList
          .map((s) => Currency.fromJson(jsonDecode(s as String) as Map<String, dynamic>))
          .toList();
    }
  }

  /// Save custom currencies to storage.
  static Future<void> _saveCustomCurrencies() async {
    final config = ConfigService();
    final jsonList = _customCurrencies.map((c) => jsonEncode(c.toJson())).toList();
    config.set(_customCurrenciesKey, jsonList);
  }

  /// Add a custom currency.
  ///
  /// Returns true if added, false if code already exists.
  static Future<bool> addCustomCurrency({
    required String code,
    required String name,
    String? symbol,
    int decimals = 2,
  }) async {
    final upperCode = code.toUpperCase();

    // Check if already exists
    if (byCode(upperCode) != null) {
      return false;
    }

    final currency = Currency.custom(
      code: upperCode,
      name: name,
      symbol: symbol,
      decimals: decimals,
    );

    _customCurrencies.add(currency);
    await _saveCustomCurrencies();
    return true;
  }

  /// Remove a custom currency.
  ///
  /// Returns true if removed, false if not found or not custom.
  static Future<bool> removeCustomCurrency(String code) async {
    final upperCode = code.toUpperCase();
    final index = _customCurrencies.indexWhere((c) => c.code == upperCode);
    if (index == -1) {
      return false;
    }

    _customCurrencies.removeAt(index);
    await _saveCustomCurrencies();
    return true;
  }

  /// Update a custom currency.
  static Future<bool> updateCustomCurrency({
    required String code,
    required String name,
    String? symbol,
    int decimals = 2,
  }) async {
    final upperCode = code.toUpperCase();
    final index = _customCurrencies.indexWhere((c) => c.code == upperCode);
    if (index == -1) {
      return false;
    }

    _customCurrencies[index] = Currency.custom(
      code: upperCode,
      name: name,
      symbol: symbol,
      decimals: decimals,
    );
    await _saveCustomCurrencies();
    return true;
  }

  /// Get currency by code.
  static Currency? byCode(String code) {
    final upperCode = code.toUpperCase();
    try {
      return all.firstWhere((c) => c.code == upperCode);
    } catch (_) {
      return null;
    }
  }

  /// Check if a currency code is valid.
  static bool isValid(String code) => byCode(code) != null;

  /// Check if a currency code represents time.
  static bool isTimeCurrency(String code) {
    final upper = code.toUpperCase();
    return upper == 'MIN' || upper == 'HOUR' || upper == 'DAY' ||
           upper == 'WEEK' || upper == 'MONTH';
  }

  /// Check if a currency code is a cryptocurrency.
  static bool isCryptoCurrency(String code) {
    final currency = byCode(code);
    return currency?.isCrypto ?? false;
  }

  /// Check if a currency code is custom.
  static bool isCustomCurrency(String code) {
    final currency = byCode(code);
    return currency?.isCustom ?? false;
  }
}

/// Format a time amount based on currency unit.
///
/// Examples:
/// - 30 MIN → "30m"
/// - 2.5 HOUR → "2h 30m"
/// - 3 DAY → "3 days"
/// - 2 WEEK → "2 weeks"
/// - 1.5 MONTH → "1 month 2 weeks"
String formatTimeAmount(double amount, String currencyCode) {
  final code = currencyCode.toUpperCase();

  // Convert to minutes first for consistent formatting
  int minutes;
  switch (code) {
    case 'MIN':
      minutes = amount.round();
      break;
    case 'HOUR':
      minutes = (amount * 60).round();
      break;
    case 'DAY':
      minutes = (amount * 1440).round();
      break;
    case 'WEEK':
      minutes = (amount * 10080).round();
      break;
    case 'MONTH':
      // Approximate month as 30 days
      minutes = (amount * 43200).round();
      break;
    default:
      minutes = amount.round();
  }

  return formatDuration(minutes);
}

/// Format a duration in minutes to human-readable string.
///
/// Examples:
/// - 30 → "30m"
/// - 90 → "1h 30m"
/// - 480 → "8h"
/// - 1440 → "1 day"
/// - 10080 → "1 week"
String formatDuration(int minutes) {
  if (minutes < 0) {
    return '-${formatDuration(-minutes)}';
  }
  if (minutes == 0) {
    return '0m';
  }

  // 1 month = 30 days = 43200 minutes
  final months = minutes ~/ 43200;
  final remainingAfterMonths = minutes % 43200;
  final weeks = remainingAfterMonths ~/ 10080;
  final remainingAfterWeeks = remainingAfterMonths % 10080;
  final days = remainingAfterWeeks ~/ 1440;
  final remainingAfterDays = remainingAfterWeeks % 1440;
  final hours = remainingAfterDays ~/ 60;
  final mins = remainingAfterDays % 60;

  final parts = <String>[];

  if (months > 0) {
    parts.add('$months ${months == 1 ? 'month' : 'months'}');
  }
  if (weeks > 0) {
    parts.add('$weeks ${weeks == 1 ? 'week' : 'weeks'}');
  }
  if (days > 0) {
    parts.add('$days ${days == 1 ? 'day' : 'days'}');
  }
  if (hours > 0) {
    parts.add('${hours}h');
  }
  if (mins > 0) {
    parts.add('${mins}m');
  }

  // Limit to 2 most significant parts for readability
  if (parts.length > 2) {
    return parts.take(2).join(' ');
  }

  return parts.join(' ');
}

/// Parse a duration string back to minutes.
///
/// Supports formats like:
/// - "30m" → 30
/// - "1h 30m" → 90
/// - "8h" → 480
/// - "1 day" → 1440
/// - "2 weeks 3 days" → 18720
/// - "1 month" → 43200
int? parseDuration(String input) {
  if (input.isEmpty) return null;

  final normalized = input.toLowerCase().trim();
  int total = 0;

  // Try parsing as plain number (minutes)
  final plainNumber = int.tryParse(normalized);
  if (plainNumber != null) {
    return plainNumber;
  }

  // Parse month/months
  final monthMatch = RegExp(r'(\d+)\s*months?').firstMatch(normalized);
  if (monthMatch != null) {
    total += int.parse(monthMatch.group(1)!) * 43200;
  }

  // Parse week/weeks
  final weekMatch = RegExp(r'(\d+)\s*weeks?').firstMatch(normalized);
  if (weekMatch != null) {
    total += int.parse(weekMatch.group(1)!) * 10080;
  }

  // Parse day/days
  final dayMatch = RegExp(r'(\d+)\s*days?').firstMatch(normalized);
  if (dayMatch != null) {
    total += int.parse(dayMatch.group(1)!) * 1440;
  }

  // Parse hours (h)
  final hourMatch = RegExp(r'(\d+)\s*h(?:ours?)?').firstMatch(normalized);
  if (hourMatch != null) {
    total += int.parse(hourMatch.group(1)!) * 60;
  }

  // Parse minutes (m)
  final minMatch = RegExp(r'(\d+)\s*m(?:in(?:ute)?s?)?').firstMatch(normalized);
  if (minMatch != null) {
    total += int.parse(minMatch.group(1)!);
  }

  return total > 0 ? total : null;
}

/// Format a duration for compact display (e.g., in lists).
///
/// Returns shorter format: "30m", "1.5h", "2d", "1w", "2mo"
String formatDurationCompact(int minutes) {
  if (minutes < 0) {
    return '-${formatDurationCompact(-minutes)}';
  }
  if (minutes == 0) {
    return '0m';
  }

  // 1 month = 30 days = 43200 minutes
  if (minutes >= 43200) {
    final months = minutes / 43200;
    if (months == months.roundToDouble()) {
      return '${months.toInt()}mo';
    }
    return '${months.toStringAsFixed(1)}mo';
  }

  if (minutes >= 10080) {
    final weeks = minutes / 10080;
    if (weeks == weeks.roundToDouble()) {
      return '${weeks.toInt()}w';
    }
    return '${weeks.toStringAsFixed(1)}w';
  }

  if (minutes >= 1440) {
    final days = minutes / 1440;
    if (days == days.roundToDouble()) {
      return '${days.toInt()}d';
    }
    return '${days.toStringAsFixed(1)}d';
  }

  if (minutes >= 60) {
    final hours = minutes / 60;
    if (hours == hours.roundToDouble()) {
      return '${hours.toInt()}h';
    }
    return '${hours.toStringAsFixed(1)}h';
  }

  return '${minutes}m';
}
