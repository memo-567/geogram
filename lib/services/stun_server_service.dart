/// Self-hosted STUN Server Service
///
/// Implements RFC 5389 STUN Binding method for WebRTC NAT traversal.
/// Replaces external STUN servers (Google, Twilio, Mozilla) with
/// privacy-respecting self-hosted capability on station servers.
///
/// Protocol:
/// - Server receives UDP Binding Request on port 3478
/// - Server responds with XOR-MAPPED-ADDRESS (client's public IP:port)
/// - Enables WebRTC peers to discover their public address
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'log_service.dart';

/// STUN message types (RFC 5389)
class StunMessageType {
  static const int bindingRequest = 0x0001;
  static const int bindingResponse = 0x0101;
  static const int bindingErrorResponse = 0x0111;
}

/// STUN attribute types (RFC 5389)
class StunAttributeType {
  static const int mappedAddress = 0x0001;
  static const int xorMappedAddress = 0x0020;
  static const int software = 0x8022;
  static const int fingerprint = 0x8028;
}

/// STUN magic cookie (RFC 5389)
const int stunMagicCookie = 0x2112A442;

/// STUN Server Service
///
/// Implements a minimal STUN server supporting only the Binding method
/// needed for WebRTC NAT traversal. No logging of client IPs for privacy.
class StunServerService {
  static final StunServerService _instance = StunServerService._internal();
  factory StunServerService() => _instance;
  StunServerService._internal();

  RawDatagramSocket? _socket;
  bool _running = false;
  int _port = 3478;
  int _requestsHandled = 0;

  /// Whether the STUN server is running
  bool get isRunning => _running;

  /// Current port (only valid when running)
  int get port => _port;

  /// Number of requests handled since start
  int get requestsHandled => _requestsHandled;

  /// Software name for SOFTWARE attribute
  static const String _softwareName = 'Geogram STUN 1.0';

  /// Start the STUN server
  ///
  /// [port] - UDP port to listen on (default: 3478, standard STUN port)
  /// Returns true if started successfully, false on error
  Future<bool> start({int port = 3478}) async {
    if (_running) {
      LogService().log('STUN server already running on port $_port');
      return true;
    }

    try {
      _port = port;
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );

      _socket!.listen(
        _handleDatagram,
        onError: (error) {
          LogService().log('STUN server error: $error');
        },
        onDone: () {
          LogService().log('STUN server socket closed');
          _running = false;
        },
      );

      _running = true;
      _requestsHandled = 0;
      LogService().log('STUN server started on UDP port $port');
      return true;
    } catch (e) {
      LogService().log('Failed to start STUN server: $e');
      return false;
    }
  }

  /// Stop the STUN server
  Future<void> stop() async {
    if (!_running) return;

    _socket?.close();
    _socket = null;
    _running = false;
    LogService().log('STUN server stopped (handled $_requestsHandled requests)');
  }

  /// Handle incoming UDP datagram
  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    final data = datagram.data;
    final address = datagram.address;
    final port = datagram.port;

    // Validate minimum STUN header size (20 bytes)
    if (data.length < 20) {
      return; // Silently ignore malformed packets
    }

    // Parse STUN header
    final messageType = (data[0] << 8) | data[1];
    final messageLength = (data[2] << 8) | data[3];
    final magicCookie = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];

    // Validate magic cookie (RFC 5389)
    if (magicCookie != stunMagicCookie) {
      return; // Not a valid STUN message
    }

    // Extract transaction ID (12 bytes after magic cookie)
    final transactionId = data.sublist(8, 20);

    // Validate message length
    if (data.length != 20 + messageLength) {
      return; // Invalid message length
    }

    // Handle Binding Request
    if (messageType == StunMessageType.bindingRequest) {
      _handleBindingRequest(address, port, transactionId);
    }
  }

  /// Handle STUN Binding Request
  ///
  /// Responds with Binding Response containing XOR-MAPPED-ADDRESS
  void _handleBindingRequest(
    InternetAddress clientAddress,
    int clientPort,
    Uint8List transactionId,
  ) {
    _requestsHandled++;

    // Build Binding Response
    final response = _buildBindingResponse(
      clientAddress,
      clientPort,
      transactionId,
    );

    // Send response back to client
    _socket?.send(response, clientAddress, clientPort);
  }

  /// Build STUN Binding Response message
  ///
  /// Contains:
  /// - XOR-MAPPED-ADDRESS attribute (client's public IP:port, XOR'd)
  /// - SOFTWARE attribute (server identification)
  Uint8List _buildBindingResponse(
    InternetAddress clientAddress,
    int clientPort,
    Uint8List transactionId,
  ) {
    // Build attributes
    final xorMappedAddress = _buildXorMappedAddress(
      clientAddress,
      clientPort,
      transactionId,
    );
    final software = _buildSoftwareAttribute();

    // Calculate total attributes length
    final attributesLength = xorMappedAddress.length + software.length;

    // Build STUN header (20 bytes)
    final header = Uint8List(20);
    final headerView = ByteData.view(header.buffer);

    // Message Type: Binding Response
    headerView.setUint16(0, StunMessageType.bindingResponse, Endian.big);

    // Message Length (excluding 20-byte header)
    headerView.setUint16(2, attributesLength, Endian.big);

    // Magic Cookie
    headerView.setUint32(4, stunMagicCookie, Endian.big);

    // Transaction ID (copy from request)
    header.setRange(8, 20, transactionId);

    // Combine header and attributes
    final response = Uint8List(20 + attributesLength);
    response.setRange(0, 20, header);
    response.setRange(20, 20 + xorMappedAddress.length, xorMappedAddress);
    response.setRange(
      20 + xorMappedAddress.length,
      20 + attributesLength,
      software,
    );

    return response;
  }

  /// Build XOR-MAPPED-ADDRESS attribute (RFC 5389 Section 15.2)
  ///
  /// Format:
  /// 0                   1                   2                   3
  /// 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |0 0 0 0 0 0 0 0|    Family     |         X-Port                |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                X-Address (32 bits for IPv4)                   |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  Uint8List _buildXorMappedAddress(
    InternetAddress address,
    int port,
    Uint8List transactionId,
  ) {
    // IPv4 only for now
    if (address.type != InternetAddressType.IPv4) {
      // Return empty attribute for non-IPv4 (shouldn't happen on anyIPv4 socket)
      return Uint8List(0);
    }

    // Attribute: 4-byte header + 8-byte value (IPv4)
    final attr = Uint8List(12);
    final view = ByteData.view(attr.buffer);

    // Attribute Type: XOR-MAPPED-ADDRESS
    view.setUint16(0, StunAttributeType.xorMappedAddress, Endian.big);

    // Attribute Length: 8 bytes (1 reserved + 1 family + 2 port + 4 address)
    view.setUint16(2, 8, Endian.big);

    // Reserved byte (0)
    attr[4] = 0x00;

    // Family: 0x01 for IPv4
    attr[5] = 0x01;

    // X-Port: port XOR'd with most significant 16 bits of magic cookie
    final xPort = port ^ (stunMagicCookie >> 16);
    view.setUint16(6, xPort, Endian.big);

    // X-Address: IPv4 address XOR'd with magic cookie
    final addressBytes = address.rawAddress;
    final xAddress = (addressBytes[0] << 24) |
        (addressBytes[1] << 16) |
        (addressBytes[2] << 8) |
        addressBytes[3];
    final xoredAddress = xAddress ^ stunMagicCookie;
    view.setUint32(8, xoredAddress, Endian.big);

    return attr;
  }

  /// Build SOFTWARE attribute (RFC 5389 Section 15.10)
  ///
  /// Identifies the server software. Padded to multiple of 4 bytes.
  Uint8List _buildSoftwareAttribute() {
    final softwareBytes = _softwareName.codeUnits;
    final valueLength = softwareBytes.length;

    // Pad to multiple of 4 bytes
    final paddedLength = (valueLength + 3) & ~3;

    // Attribute: 4-byte header + padded value
    final attr = Uint8List(4 + paddedLength);
    final view = ByteData.view(attr.buffer);

    // Attribute Type: SOFTWARE
    view.setUint16(0, StunAttributeType.software, Endian.big);

    // Attribute Length (before padding)
    view.setUint16(2, valueLength, Endian.big);

    // Value
    attr.setRange(4, 4 + valueLength, softwareBytes);

    // Padding bytes are already 0 (Uint8List initializes to 0)

    return attr;
  }

  /// Get server status for /api/status endpoint
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _running,
      'port': _port,
      'requests_handled': _requestsHandled,
    };
  }
}
