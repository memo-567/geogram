/// Callsign generator for relay mode (X3 callsigns)
class CallsignGenerator {
  /// Derives X3 callsign from npub (deterministic)
  /// Example: npub1qcmh5... → X3QCMH
  static String deriveRelayCallsign(String npub) {
    if (!npub.startsWith('npub1')) return 'X3XXXX';
    final data = npub.substring(5); // Remove 'npub1'
    final chars = data
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .substring(0, 4)
        .padRight(4, 'X');
    return 'X3$chars';
  }

  /// Check if a callsign is a relay callsign (starts with X3)
  static bool isRelayCallsign(String callsign) {
    return callsign.startsWith('X3') && callsign.length == 6;
  }

  /// Validate callsign format
  static bool isValidCallsign(String callsign) {
    if (callsign.isEmpty) return false;
    // Must be alphanumeric and between 3-10 characters
    if (!RegExp(r'^[A-Z0-9]{3,10}$').hasMatch(callsign.toUpperCase())) {
      return false;
    }
    return true;
  }

  /// Get callsign type description
  static String getCallsignType(String callsign) {
    if (isRelayCallsign(callsign)) {
      return 'Relay (X3)';
    }
    return 'Standard';
  }
}
