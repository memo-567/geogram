/// CAPABILITIES command utilities.
library;

/// Standard NNTP capabilities from RFC 3977 and extensions.
class NNTPCapability {
  /// Version of NNTP supported.
  static const version = 'VERSION';

  /// Reader mode supported.
  static const reader = 'READER';

  /// IHAVE command supported.
  static const ihave = 'IHAVE';

  /// POST command supported.
  static const post = 'POST';

  /// NEWNEWS command supported.
  static const newnews = 'NEWNEWS';

  /// HDR command supported (RFC 3977).
  static const hdr = 'HDR';

  /// OVER command supported (RFC 3977).
  static const over = 'OVER';

  /// LIST extensions supported.
  static const list = 'LIST';

  /// STARTTLS supported.
  static const starttls = 'STARTTLS';

  /// AUTHINFO supported.
  static const authinfo = 'AUTHINFO';

  /// SASL authentication supported.
  static const sasl = 'SASL';

  /// MODE-READER supported.
  static const modeReader = 'MODE-READER';

  /// COMPRESS supported.
  static const compress = 'COMPRESS';

  /// STREAMING supported (for transit servers).
  static const streaming = 'STREAMING';

  /// Legacy XOVER supported (pre-RFC 3977).
  static const xover = 'XOVER';

  /// Legacy XHDR supported (pre-RFC 3977).
  static const xhdr = 'XHDR';

  /// Parses capabilities from CAPABILITIES response.
  static Map<String, List<String>> parse(List<String> lines) {
    final capabilities = <String, List<String>>{};

    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;

      final name = parts.first.toUpperCase();
      final args = parts.length > 1 ? parts.sublist(1) : <String>[];
      capabilities[name] = args;
    }

    return capabilities;
  }

  /// Checks if a capability is present.
  static bool hasCapability(Set<String> capabilities, String name) {
    return capabilities.contains(name.toUpperCase());
  }

  /// Checks if OVER or XOVER is supported.
  static bool hasOverview(Set<String> capabilities) {
    return hasCapability(capabilities, over) ||
        hasCapability(capabilities, xover);
  }

  /// Checks if HDR or XHDR is supported.
  static bool hasHeader(Set<String> capabilities) {
    return hasCapability(capabilities, hdr) ||
        hasCapability(capabilities, xhdr);
  }
}
