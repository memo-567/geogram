/// Full-screen proof code display for identity verification photos.
///
/// Shows a unique code (date, transaction ID, parties) that the person
/// being photographed displays on their phone screen. This provides
/// evidence that the photo was taken specifically for this transaction
/// and cannot be an old photo since the code is unique and the photo's
/// SHA1 hash will be included in the signed debt entry.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Data for generating a proof code
class ProofCodeData {
  /// Debt ID (or pending transaction ID)
  final String transactionId;

  /// Creditor callsign
  final String creditor;

  /// Debtor callsign
  final String debtor;

  /// Amount and currency
  final String amount;

  /// Optional description
  final String? description;

  /// Timestamp when code was generated
  final DateTime generatedAt;

  ProofCodeData({
    required this.transactionId,
    required this.creditor,
    required this.debtor,
    required this.amount,
    this.description,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  /// Generate a short verification code from the data
  String get shortCode {
    // Combine transaction ID + timestamp to create a unique short code
    final timestamp = generatedAt.millisecondsSinceEpoch;
    final combined = '$transactionId$timestamp';
    final hash = combined.hashCode.abs();
    return hash.toRadixString(36).toUpperCase().padLeft(3, '0').substring(0, 3);
  }

  /// Format the date for display
  String get formattedDate {
    final d = generatedAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Format the time for display
  String get formattedTime {
    final d = generatedAt;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }
}

/// Full-screen proof code display
class ProofCodeScreen extends StatefulWidget {
  final ProofCodeData data;

  const ProofCodeScreen({
    super.key,
    required this.data,
  });

  @override
  State<ProofCodeScreen> createState() => _ProofCodeScreenState();
}

class _ProofCodeScreenState extends State<ProofCodeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Lock to portrait and hide system UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Pulse animation for the code
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade900,
                  Colors.black,
                  Colors.blue.shade900,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top label
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'PROOF OF IDENTITY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Main verification code
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Short code - large and prominent
                        Text(
                          data.shortCode,
                          style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            letterSpacing: 8,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Divider
                        Container(
                          width: 200,
                          height: 2,
                          color: Colors.blue.shade200,
                        ),
                        const SizedBox(height: 16),
                        // Date and time
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_today,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              data.formattedDate,
                              style: TextStyle(
                                fontSize: 18,
                                fontFamily: 'monospace',
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.access_time,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              data.formattedTime,
                              style: TextStyle(
                                fontSize: 18,
                                fontFamily: 'monospace',
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Transaction details
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.receipt_long,
                        label: 'TRANSACTION',
                        value: data.transactionId,
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.person,
                        label: 'CREDITOR',
                        value: data.creditor,
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: 'DEBTOR',
                        value: data.debtor,
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.attach_money,
                        label: 'AMOUNT',
                        value: data.amount,
                        valueColor: Colors.greenAccent,
                      ),
                      if (data.description != null) ...[
                        const SizedBox(height: 12),
                        _DetailRow(
                          icon: Icons.description,
                          label: 'FOR',
                          value: data.description!,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // QR-like pattern (decorative, adds visual uniqueness)
                _VerificationPattern(code: data.shortCode),

                const Spacer(),

                // Instructions
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Show this screen while the other party takes your photo.\nTap anywhere to close.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.5)),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Decorative verification pattern based on the code
class _VerificationPattern extends StatelessWidget {
  final String code;

  const _VerificationPattern({required this.code});

  @override
  Widget build(BuildContext context) {
    // Generate a unique pattern from the code
    final random = math.Random(code.hashCode);
    final colors = [
      Colors.blue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightBlue,
    ];

    return SizedBox(
      width: 120,
      height: 40,
      child: CustomPaint(
        painter: _PatternPainter(random: random, colors: colors),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final math.Random random;
  final List<Color> colors;

  _PatternPainter({required this.random, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / 12;
    final cellHeight = size.height / 4;

    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 12; col++) {
        if (random.nextBool()) {
          final paint = Paint()
            ..color = colors[random.nextInt(colors.length)].withOpacity(0.6);
          canvas.drawRect(
            Rect.fromLTWH(
              col * cellWidth,
              row * cellHeight,
              cellWidth - 1,
              cellHeight - 1,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Helper to show the proof code screen
Future<void> showProofCodeScreen(
  BuildContext context, {
  required String transactionId,
  required String creditor,
  required String debtor,
  required String amount,
  String? description,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => ProofCodeScreen(
        data: ProofCodeData(
          transactionId: transactionId,
          creditor: creditor,
          debtor: debtor,
          amount: amount,
          description: description,
        ),
      ),
    ),
  );
}
