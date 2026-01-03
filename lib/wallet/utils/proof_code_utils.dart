/// Utility functions for proof code generation and verification.
///
/// Proof codes are used to verify that a photo was taken specifically
/// for a particular transaction at a specific time. The person being
/// photographed shows this code on their phone screen.
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Generates and validates proof codes for identity verification photos.
class ProofCodeUtils {
  ProofCodeUtils._();

  /// Generate a proof code from transaction data.
  ///
  /// The code is deterministic - same inputs produce same outputs.
  /// This allows verification that a code matches a transaction.
  /// Returns a 3-character alphanumeric code.
  static String generateCode({
    required String transactionId,
    required String creditor,
    required String debtor,
    required DateTime timestamp,
  }) {
    // Combine all data into a string
    final data = '$transactionId|$creditor|$debtor|${timestamp.millisecondsSinceEpoch}';

    // Hash it
    final bytes = utf8.encode(data);
    final hash = sha256.convert(bytes);

    // Take first 3 characters in base36 (alphanumeric)
    final hashInt = hash.bytes.take(2).fold<int>(0, (a, b) => (a << 8) | b);
    return hashInt.toRadixString(36).toUpperCase().padLeft(3, '0').substring(0, 3);
  }

  /// Verify a proof code matches the transaction data.
  static bool verifyCode({
    required String code,
    required String transactionId,
    required String creditor,
    required String debtor,
    required DateTime timestamp,
    Duration tolerance = const Duration(minutes: 30),
  }) {
    // Check exact match first
    final expected = generateCode(
      transactionId: transactionId,
      creditor: creditor,
      debtor: debtor,
      timestamp: timestamp,
    );

    if (code == expected) return true;

    // Check within tolerance window (in case of slight time differences)
    for (int i = -30; i <= 30; i++) {
      final adjustedTime = timestamp.add(Duration(minutes: i));
      final adjusted = generateCode(
        transactionId: transactionId,
        creditor: creditor,
        debtor: debtor,
        timestamp: adjustedTime,
      );
      if (code == adjusted) return true;
    }

    return false;
  }

  /// Calculate SHA1 hash of a file.
  ///
  /// Returns lowercase hex string.
  static Future<String> calculateFileSha1(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  /// Calculate SHA1 hash of bytes.
  static String calculateBytesSha1(List<int> bytes) {
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  /// Generate a full proof data string that can be embedded in photos.
  ///
  /// Format: PROOF|{code}|{date}|{time}|{transaction}|{creditor}|{debtor}|{amount}
  static String generateProofString({
    required String transactionId,
    required String creditor,
    required String debtor,
    required String amount,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    final code = generateCode(
      transactionId: transactionId,
      creditor: creditor,
      debtor: debtor,
      timestamp: ts,
    );

    final date = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
    final time = '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';

    return 'PROOF|$code|$date|$time|$transactionId|$creditor|$debtor|$amount';
  }

  /// Parse a proof string and extract its components.
  static ProofData? parseProofString(String proofString) {
    final parts = proofString.split('|');
    if (parts.length < 8 || parts[0] != 'PROOF') {
      return null;
    }

    try {
      final dateParts = parts[2].split('-');
      final timeParts = parts[3].split(':');
      final timestamp = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );

      return ProofData(
        code: parts[1],
        timestamp: timestamp,
        transactionId: parts[4],
        creditor: parts[5],
        debtor: parts[6],
        amount: parts[7],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Parsed proof data
class ProofData {
  final String code;
  final DateTime timestamp;
  final String transactionId;
  final String creditor;
  final String debtor;
  final String amount;

  ProofData({
    required this.code,
    required this.timestamp,
    required this.transactionId,
    required this.creditor,
    required this.debtor,
    required this.amount,
  });

  /// Verify this proof data matches its code.
  bool verify() {
    return ProofCodeUtils.verifyCode(
      code: code,
      transactionId: transactionId,
      creditor: creditor,
      debtor: debtor,
      timestamp: timestamp,
    );
  }

  /// Age of the proof in minutes.
  int get ageMinutes {
    return DateTime.now().difference(timestamp).inMinutes;
  }

  /// Whether the proof is recent (within 1 hour).
  bool get isRecent => ageMinutes <= 60;

  /// Whether the proof is fresh (within 15 minutes).
  bool get isFresh => ageMinutes <= 15;

  @override
  String toString() {
    return 'ProofData(code: $code, transaction: $transactionId, age: ${ageMinutes}m)';
  }
}

/// Helper class to create and verify proof photos
class ProofPhotoHelper {
  final String transactionId;
  final String creditor;
  final String debtor;
  final String amount;
  final DateTime timestamp;
  final String code;

  ProofPhotoHelper._({
    required this.transactionId,
    required this.creditor,
    required this.debtor,
    required this.amount,
    required this.timestamp,
    required this.code,
  });

  /// Create a new proof photo helper for a transaction.
  factory ProofPhotoHelper.create({
    required String transactionId,
    required String creditor,
    required String debtor,
    required String amount,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now();
    final code = ProofCodeUtils.generateCode(
      transactionId: transactionId,
      creditor: creditor,
      debtor: debtor,
      timestamp: ts,
    );

    return ProofPhotoHelper._(
      transactionId: transactionId,
      creditor: creditor,
      debtor: debtor,
      amount: amount,
      timestamp: ts,
      code: code,
    );
  }

  /// Get the proof string for embedding.
  String get proofString => ProofCodeUtils.generateProofString(
    transactionId: transactionId,
    creditor: creditor,
    debtor: debtor,
    amount: amount,
    timestamp: timestamp,
  );

  /// Verify a photo file matches this proof.
  ///
  /// Returns the SHA1 hash if the file exists.
  Future<String?> getPhotoHash(String filePath) async {
    try {
      return await ProofCodeUtils.calculateFileSha1(filePath);
    } catch (_) {
      return null;
    }
  }

  /// Create metadata for a debt entry that includes proof photo info.
  Map<String, String> createPhotoMetadata({
    required String filename,
    required String sha1,
  }) {
    return {
      'file': filename,
      'sha1': sha1,
      'proof_code': code,
      'proof_timestamp': timestamp.millisecondsSinceEpoch.toString(),
    };
  }
}
