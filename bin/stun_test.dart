#!/usr/bin/env dart
/// STUN Server Test Script
///
/// Tests the self-hosted STUN server by sending a Binding Request
/// and verifying the XOR-MAPPED-ADDRESS response.
///
/// Usage:
///   dart run bin/stun_test.dart [host] [port]
///
/// Examples:
///   dart run bin/stun_test.dart localhost 3478
///   dart run bin/stun_test.dart 192.168.1.100 3478
///   dart run bin/stun_test.dart p2p.radio 3478

import 'dart:io';
import 'dart:typed_data';

/// STUN magic cookie (RFC 5389)
const int stunMagicCookie = 0x2112A442;

/// STUN message types
const int bindingRequest = 0x0001;
const int bindingResponse = 0x0101;

/// STUN attribute types
const int attrXorMappedAddress = 0x0020;
const int attrSoftware = 0x8022;

void main(List<String> args) async {
  final host = args.isNotEmpty ? args[0] : 'localhost';
  final port = args.length > 1 ? int.parse(args[1]) : 3478;

  print('STUN Test Client');
  print('================');
  print('Target: $host:$port');
  print('');

  try {
    // Create UDP socket
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    print('Local socket bound to ${socket.address.address}:${socket.port}');

    // Build STUN Binding Request
    final request = buildBindingRequest();
    print('Sending Binding Request (${request.length} bytes)...');

    // Resolve hostname
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      print('ERROR: Could not resolve hostname: $host');
      socket.close();
      exit(1);
    }
    final targetAddress = addresses.first;
    print('Resolved $host to ${targetAddress.address}');

    // Send request
    final bytesSent = socket.send(request, targetAddress, port);
    print('Sent $bytesSent bytes');

    // Wait for response with timeout
    print('Waiting for response...');

    Datagram? response;
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed.inSeconds < 5) {
      await Future.delayed(const Duration(milliseconds: 100));
      response = socket.receive();
      if (response != null) break;
    }

    if (response == null) {
      print('');
      print('ERROR: No response received within 5 seconds');
      print('');
      print('Possible causes:');
      print('  - STUN server not running on $host:$port');
      print('  - Firewall blocking UDP port $port');
      print('  - Wrong host/port');
      socket.close();
      exit(1);
    }

    print('Received response (${response.data.length} bytes) in ${stopwatch.elapsedMilliseconds}ms');
    print('');

    // Parse response
    parseBindingResponse(response.data);

    socket.close();
    print('');
    print('SUCCESS: STUN server is working correctly!');
  } catch (e) {
    print('ERROR: $e');
    exit(1);
  }
}

/// Build a STUN Binding Request message
Uint8List buildBindingRequest() {
  final request = Uint8List(20); // Minimum STUN message is 20 bytes
  final view = ByteData.view(request.buffer);

  // Message Type: Binding Request (0x0001)
  view.setUint16(0, bindingRequest, Endian.big);

  // Message Length: 0 (no attributes)
  view.setUint16(2, 0, Endian.big);

  // Magic Cookie
  view.setUint32(4, stunMagicCookie, Endian.big);

  // Transaction ID: 12 random bytes
  final random = DateTime.now().millisecondsSinceEpoch;
  for (int i = 8; i < 20; i++) {
    request[i] = ((random >> ((i - 8) * 4)) & 0xFF);
  }

  return request;
}

/// Parse and display a STUN Binding Response
void parseBindingResponse(Uint8List data) {
  if (data.length < 20) {
    print('ERROR: Response too short (${data.length} bytes)');
    return;
  }

  final view = ByteData.view(data.buffer);

  // Parse header
  final messageType = view.getUint16(0, Endian.big);
  final messageLength = view.getUint16(2, Endian.big);
  final magicCookie = view.getUint32(4, Endian.big);

  print('Response Header:');
  print('  Message Type: 0x${messageType.toRadixString(16).padLeft(4, '0')}');

  if (messageType != bindingResponse) {
    print('  WARNING: Expected Binding Response (0x0101)');
  } else {
    print('  Type: Binding Response (correct)');
  }

  print('  Message Length: $messageLength bytes');
  print('  Magic Cookie: 0x${magicCookie.toRadixString(16)}');

  if (magicCookie != stunMagicCookie) {
    print('  WARNING: Invalid magic cookie!');
    return;
  } else {
    print('  Magic Cookie: Valid');
  }

  // Parse attributes
  print('');
  print('Attributes:');

  int offset = 20;
  while (offset + 4 <= data.length) {
    final attrType = view.getUint16(offset, Endian.big);
    final attrLength = view.getUint16(offset + 2, Endian.big);

    if (offset + 4 + attrLength > data.length) {
      print('  ERROR: Attribute length exceeds message');
      break;
    }

    if (attrType == attrXorMappedAddress) {
      print('  XOR-MAPPED-ADDRESS:');
      parseXorMappedAddress(data, offset + 4, attrLength);
    } else if (attrType == attrSoftware) {
      final softwareBytes = data.sublist(offset + 4, offset + 4 + attrLength);
      final software = String.fromCharCodes(softwareBytes);
      print('  SOFTWARE: "$software"');
    } else {
      print('  Unknown attribute 0x${attrType.toRadixString(16)}: $attrLength bytes');
    }

    // Move to next attribute (padded to 4-byte boundary)
    offset += 4 + ((attrLength + 3) & ~3);
  }
}

/// Parse XOR-MAPPED-ADDRESS attribute
void parseXorMappedAddress(Uint8List data, int offset, int length) {
  if (length < 8) {
    print('    ERROR: Attribute too short');
    return;
  }

  final view = ByteData.view(data.buffer);

  final family = data[offset + 1];
  final xPort = view.getUint16(offset + 2, Endian.big);
  final xAddress = view.getUint32(offset + 4, Endian.big);

  // XOR to get real values
  final port = xPort ^ (stunMagicCookie >> 16);
  final address = xAddress ^ stunMagicCookie;

  // Convert address to dotted notation
  final a1 = (address >> 24) & 0xFF;
  final a2 = (address >> 16) & 0xFF;
  final a3 = (address >> 8) & 0xFF;
  final a4 = address & 0xFF;
  final ipAddress = '$a1.$a2.$a3.$a4';

  print('    Family: ${family == 1 ? "IPv4" : "IPv6 (0x${family.toRadixString(16)})"}');
  print('    Address: $ipAddress');
  print('    Port: $port');
  print('');
  print('Your public address as seen by the STUN server: $ipAddress:$port');
}
