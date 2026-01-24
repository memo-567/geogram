import 'flash_protocol.dart';
import 'esptool_protocol.dart';

/// Protocol factory and registry
///
/// Manages available flash protocols and creates instances.
class ProtocolRegistry {
  /// Registered protocol factories
  static final Map<String, FlashProtocol Function()> _protocols = {
    'esptool': () => EspToolProtocol(),
    // 'quansheng': () => QuanshengProtocol(),
  };

  /// Create a protocol instance by ID
  ///
  /// Returns null if protocol is not registered.
  static FlashProtocol? create(String protocolId) {
    final factory = _protocols[protocolId];
    return factory?.call();
  }

  /// Get list of available protocol IDs
  static List<String> get availableProtocols => _protocols.keys.toList();

  /// Check if a protocol is available
  static bool isAvailable(String protocolId) {
    return _protocols.containsKey(protocolId);
  }

  /// Register a new protocol
  static void register(String protocolId, FlashProtocol Function() factory) {
    _protocols[protocolId] = factory;
  }

  /// Get protocol info
  static Map<String, String> getProtocolInfo(String protocolId) {
    final protocol = create(protocolId);
    if (protocol == null) {
      return {'id': protocolId, 'name': 'Unknown'};
    }

    return {
      'id': protocol.protocolId,
      'name': protocol.protocolName,
    };
  }

  /// Get info for all protocols
  static List<Map<String, String>> getAllProtocolInfo() {
    return availableProtocols.map((id) => getProtocolInfo(id)).toList();
  }
}
