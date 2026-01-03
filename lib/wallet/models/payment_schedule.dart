/// Payment schedule model for debts with installments and interest.
///
/// Generates a clear payment plan showing each installment date,
/// principal amount, interest amount, and total due.
library;

import 'currency.dart';

/// Represents a single payment installment in a schedule.
class PaymentInstallment {
  /// Installment number (1-based)
  final int number;

  /// Due date for this payment
  final DateTime dueDate;

  /// Principal portion of this payment
  final double principal;

  /// Interest portion of this payment
  final double interest;

  /// Total payment amount (principal + interest)
  final double total;

  /// Remaining balance after this payment
  final double remainingBalance;

  PaymentInstallment({
    required this.number,
    required this.dueDate,
    required this.principal,
    required this.interest,
    required this.total,
    required this.remainingBalance,
  });

  /// Format the due date as YYYY-MM-DD.
  String get formattedDueDate {
    return '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}';
  }

  /// Convert to map for serialization.
  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'due_date': formattedDueDate,
      'principal': principal,
      'interest': interest,
      'total': total,
      'remaining_balance': remainingBalance,
    };
  }

  /// Create from map.
  factory PaymentInstallment.fromJson(Map<String, dynamic> json) {
    return PaymentInstallment(
      number: json['number'] as int,
      dueDate: DateTime.parse(json['due_date'] as String),
      principal: (json['principal'] as num).toDouble(),
      interest: (json['interest'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      remainingBalance: (json['remaining_balance'] as num).toDouble(),
    );
  }
}

/// Complete payment schedule for a debt.
class PaymentSchedule {
  /// Original principal amount
  final double principal;

  /// Annual interest rate (as percentage, e.g., 5.0 for 5%)
  final double annualInterestRate;

  /// Currency code
  final String currency;

  /// Number of installments
  final int numberOfInstallments;

  /// Start date (first payment due date)
  final DateTime startDate;

  /// Days between payments
  final int paymentIntervalDays;

  /// List of all installments
  final List<PaymentInstallment> installments;

  /// Total interest over the life of the debt
  final double totalInterest;

  /// Total amount to be paid (principal + all interest)
  final double totalAmount;

  PaymentSchedule._({
    required this.principal,
    required this.annualInterestRate,
    required this.currency,
    required this.numberOfInstallments,
    required this.startDate,
    required this.paymentIntervalDays,
    required this.installments,
    required this.totalInterest,
    required this.totalAmount,
  });

  /// Generate a payment schedule with fixed installments.
  ///
  /// Uses simple interest calculation where interest is calculated
  /// on the remaining principal balance.
  ///
  /// [principal] - The original loan amount
  /// [annualInterestRate] - Annual interest rate as percentage (e.g., 5.0)
  /// [currency] - Currency code
  /// [numberOfInstallments] - Number of payments
  /// [startDate] - Date of first payment
  /// [paymentIntervalDays] - Days between payments (default 30 for monthly)
  factory PaymentSchedule.generate({
    required double principal,
    required double annualInterestRate,
    required String currency,
    required int numberOfInstallments,
    required DateTime startDate,
    int paymentIntervalDays = 30,
  }) {
    if (numberOfInstallments <= 0) {
      throw ArgumentError('Number of installments must be positive');
    }

    if (principal <= 0) {
      throw ArgumentError('Principal must be positive');
    }

    final installments = <PaymentInstallment>[];
    double remainingBalance = principal;
    double totalInterest = 0;

    // Calculate fixed principal payment per installment
    final principalPerPayment = principal / numberOfInstallments;

    // Daily interest rate
    final dailyRate = annualInterestRate / 100 / 365;

    for (int i = 0; i < numberOfInstallments; i++) {
      final dueDate = startDate.add(Duration(days: paymentIntervalDays * i));

      // Interest for this period (on remaining balance)
      final interestForPeriod = remainingBalance * dailyRate * paymentIntervalDays;
      totalInterest += interestForPeriod;

      // For the last installment, adjust principal to clear the balance
      final isLast = i == numberOfInstallments - 1;
      final principalPayment = isLast ? remainingBalance : principalPerPayment;

      final totalPayment = principalPayment + interestForPeriod;
      remainingBalance -= principalPayment;

      // Ensure we don't have floating point errors
      if (isLast) {
        remainingBalance = 0;
      }

      installments.add(PaymentInstallment(
        number: i + 1,
        dueDate: dueDate,
        principal: _round(principalPayment),
        interest: _round(interestForPeriod),
        total: _round(totalPayment),
        remainingBalance: _round(remainingBalance),
      ));
    }

    return PaymentSchedule._(
      principal: principal,
      annualInterestRate: annualInterestRate,
      currency: currency,
      numberOfInstallments: numberOfInstallments,
      startDate: startDate,
      paymentIntervalDays: paymentIntervalDays,
      installments: installments,
      totalInterest: _round(totalInterest),
      totalAmount: _round(principal + totalInterest),
    );
  }

  /// Generate a schedule with no interest (0%).
  factory PaymentSchedule.noInterest({
    required double principal,
    required String currency,
    required int numberOfInstallments,
    required DateTime startDate,
    int paymentIntervalDays = 30,
  }) {
    return PaymentSchedule.generate(
      principal: principal,
      annualInterestRate: 0,
      currency: currency,
      numberOfInstallments: numberOfInstallments,
      startDate: startDate,
      paymentIntervalDays: paymentIntervalDays,
    );
  }

  /// Generate a single payment schedule (no installments).
  factory PaymentSchedule.singlePayment({
    required double principal,
    required String currency,
    required DateTime dueDate,
    double annualInterestRate = 0,
  }) {
    // Calculate days from now to due date for interest
    final daysUntilDue = dueDate.difference(DateTime.now()).inDays;
    final dailyRate = annualInterestRate / 100 / 365;
    final interest = principal * dailyRate * daysUntilDue;

    return PaymentSchedule._(
      principal: principal,
      annualInterestRate: annualInterestRate,
      currency: currency,
      numberOfInstallments: 1,
      startDate: dueDate,
      paymentIntervalDays: daysUntilDue,
      installments: [
        PaymentInstallment(
          number: 1,
          dueDate: dueDate,
          principal: principal,
          interest: _round(interest),
          total: _round(principal + interest),
          remainingBalance: 0,
        ),
      ],
      totalInterest: _round(interest),
      totalAmount: _round(principal + interest),
    );
  }

  /// Round to 2 decimal places.
  static double _round(double value) {
    return (value * 100).round() / 100;
  }

  /// Get the final due date (last payment date).
  DateTime get finalDueDate => installments.last.dueDate;

  /// Get currency object.
  Currency? get currencyObj => Currencies.byCode(currency);

  /// Format amount with currency symbol.
  String formatAmount(double amount) {
    final curr = currencyObj;
    if (curr != null) {
      return curr.format(amount);
    }
    return '${amount.toStringAsFixed(2)} $currency';
  }

  /// Generate markdown representation of the schedule.
  ///
  /// This is included in the debt contract for clarity.
  /// Shows explicit payment instructions with exact amounts and dates.
  String toMarkdown() {
    final buffer = StringBuffer();

    buffer.writeln('## Payment Plan');
    buffer.writeln();

    // Clear payment instructions
    buffer.writeln('### Payment Instructions');
    buffer.writeln();
    buffer.writeln('The debtor must make the following payments:');
    buffer.writeln();

    for (final installment in installments) {
      buffer.writeln('**Payment ${installment.number}:** Pay **${formatAmount(installment.total)}** by **${installment.formattedDueDate}**');
      if (annualInterestRate > 0) {
        buffer.writeln('  - Principal: ${formatAmount(installment.principal)}');
        buffer.writeln('  - Interest: ${formatAmount(installment.interest)}');
        buffer.writeln('  - **Total: ${formatAmount(installment.total)}**');
      }
      buffer.writeln();
    }

    // Summary box
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('### Summary');
    buffer.writeln();
    buffer.writeln('| | |');
    buffer.writeln('|---|---|');
    buffer.writeln('| **Original Amount** | ${formatAmount(principal)} |');
    if (annualInterestRate > 0) {
      buffer.writeln('| **Interest Rate** | ${annualInterestRate.toStringAsFixed(2)}% per year |');
      buffer.writeln('| **Total Interest** | ${formatAmount(totalInterest)} |');
    }
    buffer.writeln('| **Total to Pay** | **${formatAmount(totalAmount)}** |');
    buffer.writeln('| **Number of Payments** | $numberOfInstallments |');
    buffer.writeln('| **First Payment** | ${installments.first.formattedDueDate} |');
    buffer.writeln('| **Last Payment** | ${installments.last.formattedDueDate} |');
    buffer.writeln();

    // Detailed breakdown table
    buffer.writeln('### Detailed Payment Schedule');
    buffer.writeln();
    buffer.writeln('| Payment | Due Date | Amount to Pay | Principal | Interest | Balance After |');
    buffer.writeln('|---------|----------|---------------|-----------|----------|---------------|');

    for (final installment in installments) {
      buffer.writeln(
        '| ${installment.number} '
        '| ${installment.formattedDueDate} '
        '| **${formatAmount(installment.total)}** '
        '| ${formatAmount(installment.principal)} '
        '| ${formatAmount(installment.interest)} '
        '| ${formatAmount(installment.remainingBalance)} |',
      );
    }

    return buffer.toString();
  }

  /// Generate a text summary for display in UI.
  String toSummary() {
    final buffer = StringBuffer();

    buffer.writeln('$numberOfInstallments payments of approximately ${formatAmount(installments.first.total)}');
    if (annualInterestRate > 0) {
      buffer.writeln('Interest rate: ${annualInterestRate.toStringAsFixed(2)}% per year');
      buffer.writeln('Total interest: ${formatAmount(totalInterest)}');
    }
    buffer.writeln('Total to pay: ${formatAmount(totalAmount)}');
    buffer.writeln('Final payment due: ${installments.last.formattedDueDate}');

    return buffer.toString();
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'principal': principal,
      'annual_interest_rate': annualInterestRate,
      'currency': currency,
      'number_of_installments': numberOfInstallments,
      'start_date': startDate.toIso8601String(),
      'payment_interval_days': paymentIntervalDays,
      'installments': installments.map((i) => i.toJson()).toList(),
      'total_interest': totalInterest,
      'total_amount': totalAmount,
    };
  }

  /// Create from JSON map.
  factory PaymentSchedule.fromJson(Map<String, dynamic> json) {
    return PaymentSchedule._(
      principal: (json['principal'] as num).toDouble(),
      annualInterestRate: (json['annual_interest_rate'] as num).toDouble(),
      currency: json['currency'] as String,
      numberOfInstallments: json['number_of_installments'] as int,
      startDate: DateTime.parse(json['start_date'] as String),
      paymentIntervalDays: json['payment_interval_days'] as int,
      installments: (json['installments'] as List)
          .map((i) => PaymentInstallment.fromJson(i as Map<String, dynamic>))
          .toList(),
      totalInterest: (json['total_interest'] as num).toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
    );
  }

  /// Parse schedule from debt content (markdown).
  static PaymentSchedule? parseFromMarkdown(String content) {
    // Look for the payment schedule table
    final tableRegex = RegExp(
      r'\| (\d+) \| (\d{4}-\d{2}-\d{2}) \| [^\|]+ \| [^\|]+ \| [^\|]+ \| [^\|]+ \|',
      multiLine: true,
    );

    final matches = tableRegex.allMatches(content);
    if (matches.isEmpty) return null;

    // This is a simplified parser - in practice, we'd store the JSON
    // in metadata rather than parsing markdown
    return null;
  }
}

/// Extension to add payment schedule to debt terms.
extension PaymentScheduleTerms on PaymentSchedule {
  /// Generate terms text describing the payment obligation.
  String get termsText {
    final buffer = StringBuffer();

    buffer.writeln('The debtor agrees to repay this debt according to the following schedule:');
    buffer.writeln();

    if (numberOfInstallments == 1) {
      buffer.writeln('- Single payment of ${formatAmount(totalAmount)} due on ${installments.first.formattedDueDate}');
    } else {
      buffer.writeln('- $numberOfInstallments installments');
      buffer.writeln('- Payments due every $paymentIntervalDays days starting ${installments.first.formattedDueDate}');
      buffer.writeln('- Final payment due on ${finalDueDate.toString().substring(0, 10)}');
    }

    if (annualInterestRate > 0) {
      buffer.writeln();
      buffer.writeln('Interest terms:');
      buffer.writeln('- Annual interest rate: ${annualInterestRate.toStringAsFixed(2)}%');
      buffer.writeln('- Interest calculated on remaining principal balance');
      buffer.writeln('- Total interest payable: ${formatAmount(totalInterest)}');
    }

    buffer.writeln();
    buffer.writeln('Total amount to be repaid: ${formatAmount(totalAmount)}');

    return buffer.toString();
  }
}
