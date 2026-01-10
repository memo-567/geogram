/// Type of expense
enum ExpenseType {
  fuel,
  toll,
  food,
  drink,
  sleep,
  ticket,
  fine,
}

/// Type of fuel
enum FuelType {
  gasoline95,
  gasoline98,
  diesel,
  lpg,
  electric,
  hydrogen,
}

/// Supported currencies with their symbols
const Map<String, String> supportedCurrencies = {
  'EUR': '\u20ac',
  'USD': '\$',
  'GBP': '\u00a3',
  'JPY': '\u00a5',
  'CHF': 'CHF',
  'CAD': 'CA\$',
  'AUD': 'A\$',
  'CNY': '\u00a5',
  'HKD': 'HK\$',
  'NZD': 'NZ\$',
  'SEK': 'kr',
  'KRW': '\u20a9',
  'SGD': 'S\$',
  'NOK': 'kr',
  'MXN': 'MX\$',
  'INR': '\u20b9',
  'BRL': 'R\$',
  'ZAR': 'R',
  'PLN': 'z\u0142',
  'THB': '\u0e3f',
};

/// A single expense entry for a path
class TrackerExpense {
  final String id;
  final ExpenseType type;
  final double amount;
  final String currency;
  final String timestamp;
  final double? lat;
  final double? lon;
  final String? note;

  // Fuel-specific fields
  final FuelType? fuelType;
  final double? liters;
  final double? odometerKm;

  const TrackerExpense({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.timestamp,
    this.lat,
    this.lon,
    this.note,
    this.fuelType,
    this.liters,
    this.odometerKm,
  });

  DateTime get timestampDateTime {
    try {
      return DateTime.parse(timestamp);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get the currency symbol for display
  String get currencySymbol => supportedCurrencies[currency] ?? currency;

  /// Format amount with currency symbol
  String get formattedAmount => '$currencySymbol${amount.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'currency': currency,
        'timestamp': timestamp,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (note != null) 'note': note,
        if (fuelType != null) 'fuel_type': fuelType!.name,
        if (liters != null) 'liters': liters,
        if (odometerKm != null) 'odometer_km': odometerKm,
      };

  factory TrackerExpense.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = ExpenseType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ExpenseType.fuel,
    );

    FuelType? fuelType;
    final fuelTypeStr = json['fuel_type'] as String?;
    if (fuelTypeStr != null) {
      fuelType = FuelType.values.firstWhere(
        (f) => f.name == fuelTypeStr,
        orElse: () => FuelType.diesel,
      );
    }

    return TrackerExpense(
      id: json['id'] as String,
      type: type,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      timestamp: json['timestamp'] as String,
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      note: json['note'] as String?,
      fuelType: fuelType,
      liters: (json['liters'] as num?)?.toDouble(),
      odometerKm: (json['odometer_km'] as num?)?.toDouble(),
    );
  }

  TrackerExpense copyWith({
    String? id,
    ExpenseType? type,
    double? amount,
    String? currency,
    String? timestamp,
    double? lat,
    double? lon,
    String? note,
    FuelType? fuelType,
    double? liters,
    double? odometerKm,
  }) {
    return TrackerExpense(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      timestamp: timestamp ?? this.timestamp,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      note: note ?? this.note,
      fuelType: fuelType ?? this.fuelType,
      liters: liters ?? this.liters,
      odometerKm: odometerKm ?? this.odometerKm,
    );
  }
}
