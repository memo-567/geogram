/// AUTHINFO command utilities.
library;

/// Authentication methods supported by NNTP.
enum AuthMethod {
  /// Simple username/password (AUTHINFO USER/PASS).
  simple,

  /// SASL authentication.
  sasl,

  /// Generic authentication (AUTHINFO GENERIC).
  generic,
}

/// AUTHINFO response codes.
class AuthResponseCode {
  /// Authentication accepted.
  static const int accepted = 281;

  /// More authentication data needed (password after username).
  static const int continueAuth = 381;

  /// Authentication required.
  static const int required = 480;

  /// Authentication rejected.
  static const int rejected = 481;

  /// Authentication sequence error.
  static const int sequenceError = 482;

  /// Command unavailable (TLS required first, etc.).
  static const int unavailable = 483;
}

/// Formats AUTHINFO USER command.
String formatAuthUser(String username) => 'AUTHINFO USER $username';

/// Formats AUTHINFO PASS command.
String formatAuthPass(String password) => 'AUTHINFO PASS $password';

/// Parses SASL mechanisms from AUTHINFO SASL response.
///
/// Response format: "SASL PLAIN LOGIN CRAM-MD5"
List<String> parseSaslMechanisms(String response) {
  final parts = response.trim().split(RegExp(r'\s+'));
  // Skip "SASL" prefix if present
  if (parts.isNotEmpty && parts.first.toUpperCase() == 'SASL') {
    return parts.sublist(1);
  }
  return parts;
}

/// Encodes PLAIN SASL authentication.
///
/// Format: \0username\0password (null-separated, base64 encoded)
String encodePlainAuth(String username, String password) {
  final bytes = <int>[];
  bytes.add(0); // Initial null
  bytes.addAll(username.codeUnits);
  bytes.add(0); // Separator null
  bytes.addAll(password.codeUnits);

  return _base64Encode(bytes);
}

String _base64Encode(List<int> bytes) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final result = StringBuffer();

  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;

    result.write(chars[(b0 >> 2) & 0x3F]);
    result.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);

    if (i + 1 < bytes.length) {
      result.write(chars[((b1 << 2) | (b2 >> 6)) & 0x3F]);
    } else {
      result.write('=');
    }

    if (i + 2 < bytes.length) {
      result.write(chars[b2 & 0x3F]);
    } else {
      result.write('=');
    }
  }

  return result.toString();
}
