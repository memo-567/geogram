import 'tracker_expense.dart';

/// Container for path expenses (stored in expenses.json)
class TrackerExpenses {
  final String pathId;
  final List<TrackerExpense> expenses;

  const TrackerExpenses({
    required this.pathId,
    this.expenses = const [],
  });

  /// Get all fuel expenses
  List<TrackerExpense> get fuelExpenses =>
      expenses.where((e) => e.type == ExpenseType.fuel).toList();

  /// Get all toll expenses
  List<TrackerExpense> get tollExpenses =>
      expenses.where((e) => e.type == ExpenseType.toll).toList();

  /// Get all food expenses
  List<TrackerExpense> get foodExpenses =>
      expenses.where((e) => e.type == ExpenseType.food).toList();

  /// Get all drink expenses
  List<TrackerExpense> get drinkExpenses =>
      expenses.where((e) => e.type == ExpenseType.drink).toList();

  /// Get all sleep/accommodation expenses
  List<TrackerExpense> get sleepExpenses =>
      expenses.where((e) => e.type == ExpenseType.sleep).toList();

  /// Get all ticket expenses
  List<TrackerExpense> get ticketExpenses =>
      expenses.where((e) => e.type == ExpenseType.ticket).toList();

  /// Get all fine expenses
  List<TrackerExpense> get fineExpenses =>
      expenses.where((e) => e.type == ExpenseType.fine).toList();

  /// Total fuel cost (in original currencies - for display when single currency)
  double get totalFuelCost =>
      fuelExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total fuel liters
  double get totalFuelLiters =>
      fuelExpenses.fold(0.0, (sum, e) => sum + (e.liters ?? 0));

  /// Total toll cost
  double get totalTollCost =>
      tollExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total food cost
  double get totalFoodCost =>
      foodExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total drink cost
  double get totalDrinkCost =>
      drinkExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total sleep cost
  double get totalSleepCost =>
      sleepExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total ticket cost
  double get totalTicketCost =>
      ticketExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total fine cost
  double get totalFineCost =>
      fineExpenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Total of all expenses
  double get totalAllCost => expenses.fold(0.0, (sum, e) => sum + e.amount);

  /// Check if all expenses use the same currency
  bool get hasSingleCurrency {
    if (expenses.isEmpty) return true;
    final firstCurrency = expenses.first.currency;
    return expenses.every((e) => e.currency == firstCurrency);
  }

  /// Get the common currency if all expenses use the same one
  String? get commonCurrency {
    if (expenses.isEmpty) return null;
    if (!hasSingleCurrency) return null;
    return expenses.first.currency;
  }

  /// Expenses sorted by timestamp
  List<TrackerExpense> get sortedByTime {
    final sorted = List<TrackerExpense>.from(expenses);
    sorted.sort((a, b) => a.timestampDateTime.compareTo(b.timestampDateTime));
    return sorted;
  }

  Map<String, dynamic> toJson() => {
        'path_id': pathId,
        'expenses': expenses.map((e) => e.toJson()).toList(),
      };

  factory TrackerExpenses.fromJson(Map<String, dynamic> json) {
    return TrackerExpenses(
      pathId: json['path_id'] as String,
      expenses: (json['expenses'] as List<dynamic>?)
              ?.map((e) => TrackerExpense.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  TrackerExpenses copyWith({
    String? pathId,
    List<TrackerExpense>? expenses,
  }) {
    return TrackerExpenses(
      pathId: pathId ?? this.pathId,
      expenses: expenses ?? this.expenses,
    );
  }

  /// Add a new expense
  TrackerExpenses addExpense(TrackerExpense expense) {
    return copyWith(expenses: [...expenses, expense]);
  }

  /// Remove an expense by ID
  TrackerExpenses removeExpense(String expenseId) {
    return copyWith(
      expenses: expenses.where((e) => e.id != expenseId).toList(),
    );
  }

  /// Update an existing expense
  TrackerExpenses updateExpense(TrackerExpense expense) {
    return copyWith(
      expenses: expenses.map((e) => e.id == expense.id ? expense : e).toList(),
    );
  }
}

/// Fuel efficiency metrics calculated from expenses
class FuelMetrics {
  final double totalCost;
  final double totalLiters;
  final double? costPerKm;
  final double? litersPerHundredKm;
  final String? currency;

  const FuelMetrics({
    required this.totalCost,
    required this.totalLiters,
    this.costPerKm,
    this.litersPerHundredKm,
    this.currency,
  });

  /// Calculate fuel metrics from expenses and path distance
  factory FuelMetrics.fromExpenses(
    List<TrackerExpense> fuelExpenses,
    double? totalDistanceKm,
  ) {
    final totalCost = fuelExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final totalLiters = fuelExpenses.fold(0.0, (sum, e) => sum + (e.liters ?? 0));

    // Get common currency if all same
    String? currency;
    if (fuelExpenses.isNotEmpty) {
      final firstCurrency = fuelExpenses.first.currency;
      if (fuelExpenses.every((e) => e.currency == firstCurrency)) {
        currency = firstCurrency;
      }
    }

    double? costPerKm;
    double? litersPerHundredKm;

    // Need at least 2 refueling events and valid distance to calculate efficiency
    if (fuelExpenses.length >= 2 &&
        totalDistanceKm != null &&
        totalDistanceKm > 0 &&
        totalLiters > 0) {
      costPerKm = totalCost / totalDistanceKm;
      litersPerHundredKm = (totalLiters / totalDistanceKm) * 100;
    }

    return FuelMetrics(
      totalCost: totalCost,
      totalLiters: totalLiters,
      costPerKm: costPerKm,
      litersPerHundredKm: litersPerHundredKm,
      currency: currency,
    );
  }

  /// Format cost per km with currency
  String? get formattedCostPerKm {
    if (costPerKm == null || currency == null) return null;
    final symbol = supportedCurrencies[currency] ?? currency;
    return '$symbol${costPerKm!.toStringAsFixed(3)}/km';
  }

  /// Format liters per 100km
  String? get formattedLitersPerHundredKm {
    if (litersPerHundredKm == null) return null;
    return '${litersPerHundredKm!.toStringAsFixed(1)} L/100km';
  }
}
