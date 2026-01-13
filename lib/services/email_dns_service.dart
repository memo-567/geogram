/// Email DNS Diagnostics Service
///
/// Checks and diagnoses DNS configuration for email delivery:
/// - MX records (mail server routing)
/// - SPF records (sender authorization)
/// - DKIM records (email signing)
/// - DMARC records (policy enforcement)
///
/// This service is platform-agnostic and can be used by CLI or GUI.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Result of a single DNS check
class DnsCheckResult {
  final String recordType;
  final bool found;
  final String? value;
  final String? error;
  final String? recommendation;

  const DnsCheckResult({
    required this.recordType,
    required this.found,
    this.value,
    this.error,
    this.recommendation,
  });

  bool get isOk => found && error == null;

  Map<String, dynamic> toJson() => {
        'record_type': recordType,
        'found': found,
        if (value != null) 'value': value,
        if (error != null) 'error': error,
        if (recommendation != null) 'recommendation': recommendation,
      };
}

/// Complete email DNS diagnostic report
class EmailDnsReport {
  final String domain;
  final String? serverIp;
  final bool serverIpIsLocalOverride;
  final DateTime timestamp;
  final DnsCheckResult? mx;
  final DnsCheckResult? spf;
  final DnsCheckResult? dkim;
  final DnsCheckResult? dmarc;
  final DnsCheckResult? ptr;
  final DnsCheckResult? smtp;
  final List<String> recommendations;
  final bool allPassed;

  const EmailDnsReport({
    required this.domain,
    this.serverIp,
    this.serverIpIsLocalOverride = false,
    required this.timestamp,
    this.mx,
    this.spf,
    this.dkim,
    this.dmarc,
    this.ptr,
    this.smtp,
    required this.recommendations,
    required this.allPassed,
  });

  Map<String, dynamic> toJson() => {
        'domain': domain,
        if (serverIp != null) 'server_ip': serverIp,
        'server_ip_is_local_override': serverIpIsLocalOverride,
        'timestamp': timestamp.toIso8601String(),
        if (mx != null) 'mx': mx!.toJson(),
        if (spf != null) 'spf': spf!.toJson(),
        if (dkim != null) 'dkim': dkim!.toJson(),
        if (dmarc != null) 'dmarc': dmarc!.toJson(),
        if (ptr != null) 'ptr': ptr!.toJson(),
        if (smtp != null) 'smtp': smtp!.toJson(),
        'recommendations': recommendations,
        'all_passed': allPassed,
      };
}

/// Result of DKIM key generation
class DkimKeyPair {
  /// RSA private key in PEM format (for storage and signing)
  final String privateKeyPem;

  /// RSA public key in base64 format (for DNS TXT record)
  final String publicKeyBase64;

  /// The DNS TXT record value ready to use
  final String dnsRecord;

  const DkimKeyPair({
    required this.privateKeyPem,
    required this.publicKeyBase64,
    required this.dnsRecord,
  });
}

/// DKIM RSA key generator
///
/// Generates 2048-bit RSA key pairs for DKIM email signing.
/// Uses pointycastle for RSA key generation.
class DkimKeyGenerator {
  static final _secureRandom = SecureRandom('Fortuna')
    ..seed(KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256))),
    ));

  /// Generate a new DKIM RSA key pair
  ///
  /// [bitLength] - Key size: 1024 (compatible) or 2048 (more secure, but longer)
  ///               Default is 1024 for maximum DNS provider compatibility.
  ///
  /// Returns [DkimKeyPair] containing:
  /// - privateKeyPem: RSA private key in PEM format for storage
  /// - publicKeyBase64: Public key in base64 for DNS TXT record
  /// - dnsRecord: Complete DKIM DNS record value
  static DkimKeyPair generate({int bitLength = 1024}) {
    // Generate RSA key pair (1024-bit for DNS compatibility, 2048-bit for security)
    final keyParams = RSAKeyGeneratorParameters(BigInt.from(65537), bitLength, 64);
    final params = ParametersWithRandom(keyParams, _secureRandom);

    final keyGenerator = RSAKeyGenerator()..init(params);
    final keyPair = keyGenerator.generateKeyPair();

    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;

    // Encode private key to PEM format
    final privateKeyPem = _encodePrivateKeyPem(privateKey);

    // Encode public key to base64 for DNS record
    final publicKeyBytes = _encodePublicKeyDer(publicKey);
    final publicKeyBase64 = base64.encode(publicKeyBytes);

    // Create DNS record value
    final dnsRecord = 'v=DKIM1; k=rsa; p=$publicKeyBase64';

    return DkimKeyPair(
      privateKeyPem: privateKeyPem,
      publicKeyBase64: publicKeyBase64,
      dnsRecord: dnsRecord,
    );
  }

  /// Derive public key from existing private key PEM
  static String? derivePublicKeyBase64(String privateKeyPem) {
    try {
      final keyData = _decodePrivateKeyPem(privateKeyPem);
      if (keyData == null) return null;

      final publicKeyBytes = _encodePublicKeyDer(
        RSAPublicKey(keyData.modulus, keyData.publicExponent),
      );
      return base64.encode(publicKeyBytes);
    } catch (_) {
      return null;
    }
  }

  /// Encode RSA private key to PEM format
  static String _encodePrivateKeyPem(RSAPrivateKey key) {
    final bytes = _encodePrivateKeyDer(key);
    final base64Str = base64.encode(bytes);

    // Split into 64-character lines
    final lines = <String>[];
    for (var i = 0; i < base64Str.length; i += 64) {
      final end = (i + 64 < base64Str.length) ? i + 64 : base64Str.length;
      lines.add(base64Str.substring(i, end));
    }

    return '-----BEGIN RSA PRIVATE KEY-----\n${lines.join('\n')}\n-----END RSA PRIVATE KEY-----';
  }

  /// Encode RSA private key to DER format (PKCS#1)
  static Uint8List _encodePrivateKeyDer(RSAPrivateKey key) {
    final sequence = _DerSequence();
    sequence.addInteger(BigInt.zero); // version
    sequence.addInteger(key.modulus!);
    sequence.addInteger(key.publicExponent!);
    sequence.addInteger(key.privateExponent!);
    sequence.addInteger(key.p!);
    sequence.addInteger(key.q!);
    sequence.addInteger(key.privateExponent! % (key.p! - BigInt.one)); // d mod (p-1)
    sequence.addInteger(key.privateExponent! % (key.q! - BigInt.one)); // d mod (q-1)
    sequence.addInteger(key.q!.modInverse(key.p!)); // q^-1 mod p

    return sequence.encode();
  }

  /// Encode RSA public key to DER format (SubjectPublicKeyInfo)
  static Uint8List _encodePublicKeyDer(RSAPublicKey key) {
    // RSAPublicKey sequence (PKCS#1)
    final rsaPublicKey = _DerSequence();
    rsaPublicKey.addInteger(key.modulus!);
    rsaPublicKey.addInteger(key.exponent!);
    final rsaPublicKeyBytes = rsaPublicKey.encode();

    // AlgorithmIdentifier for RSA: OID 1.2.840.113549.1.1.1 + NULL
    final algorithmId = _DerSequence();
    algorithmId.addOid([1, 2, 840, 113549, 1, 1, 1]); // rsaEncryption OID
    algorithmId.addNull();
    final algorithmIdBytes = algorithmId.encode();

    // SubjectPublicKeyInfo
    final publicKeyInfo = _DerSequence();
    publicKeyInfo.addRaw(algorithmIdBytes);
    publicKeyInfo.addBitString(rsaPublicKeyBytes);

    return publicKeyInfo.encode();
  }

  /// Decode RSA private key from PEM format
  static _RsaKeyData? _decodePrivateKeyPem(String pem) {
    try {
      // Remove PEM headers and decode base64
      final lines = pem.split('\n')
          .where((line) => !line.startsWith('-----'))
          .join('');
      final bytes = base64.decode(lines);

      // Parse ASN.1 DER sequence
      final elements = _parseDerSequence(bytes);
      if (elements.length < 6) return null;

      // PKCS#1 RSAPrivateKey structure
      final modulus = _parseDerInteger(elements[1]);
      final publicExponent = _parseDerInteger(elements[2]);
      final privateExponent = _parseDerInteger(elements[3]);
      final p = _parseDerInteger(elements[4]);
      final q = _parseDerInteger(elements[5]);

      if (modulus == null || publicExponent == null ||
          privateExponent == null || p == null || q == null) {
        return null;
      }

      return _RsaKeyData(
        modulus: modulus,
        publicExponent: publicExponent,
        privateExponent: privateExponent,
        p: p,
        q: q,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse DER sequence and return list of element bytes
  static List<Uint8List> _parseDerSequence(Uint8List bytes) {
    final elements = <Uint8List>[];
    if (bytes.isEmpty || bytes[0] != 0x30) return elements; // Not a sequence

    int offset = 1;
    int length;
    (length, offset) = _parseDerLength(bytes, offset);
    if (offset < 0) return elements;

    final endOffset = offset + length;
    while (offset < endOffset && offset < bytes.length) {
      final elementStart = offset;
      offset++; // skip tag
      int elemLen;
      (elemLen, offset) = _parseDerLength(bytes, offset);
      if (offset < 0) break;
      offset += elemLen;
      elements.add(Uint8List.sublistView(bytes, elementStart, offset));
    }

    return elements;
  }

  /// Parse DER length and return (length, newOffset), or (-1, -1) on error
  static (int, int) _parseDerLength(Uint8List bytes, int offset) {
    if (offset >= bytes.length) return (-1, -1);
    final firstByte = bytes[offset++];
    if (firstByte < 0x80) {
      return (firstByte, offset);
    }
    final numBytes = firstByte & 0x7f;
    if (numBytes == 0 || offset + numBytes > bytes.length) return (-1, -1);
    int length = 0;
    for (int i = 0; i < numBytes; i++) {
      length = (length << 8) | bytes[offset++];
    }
    return (length, offset);
  }

  /// Parse DER INTEGER and return BigInt
  static BigInt? _parseDerInteger(Uint8List bytes) {
    if (bytes.isEmpty || bytes[0] != 0x02) return null; // Not an integer

    int offset = 1;
    int length;
    (length, offset) = _parseDerLength(bytes, offset);
    if (offset < 0 || offset + length > bytes.length) return null;

    // Convert bytes to BigInt (big-endian, signed)
    final valueBytes = bytes.sublist(offset, offset + length);
    BigInt value = BigInt.zero;
    for (final byte in valueBytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
}

/// Helper class for DER encoding
class _DerSequence {
  final List<Uint8List> _elements = [];

  void addInteger(BigInt value) {
    final bytes = _encodeBigInt(value);
    _elements.add(_wrapWithTagAndLength(0x02, bytes)); // INTEGER tag
  }

  void addNull() {
    _elements.add(Uint8List.fromList([0x05, 0x00])); // NULL
  }

  void addOid(List<int> oid) {
    // Encode OID: first two components combined, rest as base-128
    final bytes = <int>[];
    if (oid.length >= 2) {
      bytes.add(oid[0] * 40 + oid[1]);
      for (int i = 2; i < oid.length; i++) {
        final component = oid[i];
        if (component < 128) {
          bytes.add(component);
        } else {
          // Base-128 encoding
          final encoded = <int>[];
          int value = component;
          while (value > 0) {
            encoded.insert(0, (value & 0x7f) | (encoded.isEmpty ? 0 : 0x80));
            value >>= 7;
          }
          bytes.addAll(encoded);
        }
      }
    }
    _elements.add(_wrapWithTagAndLength(0x06, Uint8List.fromList(bytes))); // OID tag
  }

  void addBitString(Uint8List bytes) {
    // BIT STRING: prepend with 0x00 (no unused bits)
    final data = Uint8List(bytes.length + 1);
    data[0] = 0x00;
    data.setRange(1, data.length, bytes);
    _elements.add(_wrapWithTagAndLength(0x03, data)); // BIT STRING tag
  }

  void addRaw(Uint8List bytes) {
    _elements.add(bytes);
  }

  Uint8List encode() {
    // Calculate total length of contents
    int contentLength = 0;
    for (final elem in _elements) {
      contentLength += elem.length;
    }

    // Build sequence
    final content = Uint8List(contentLength);
    int offset = 0;
    for (final elem in _elements) {
      content.setRange(offset, offset + elem.length, elem);
      offset += elem.length;
    }

    return _wrapWithTagAndLength(0x30, content); // SEQUENCE tag
  }

  static Uint8List _wrapWithTagAndLength(int tag, Uint8List content) {
    final lengthBytes = _encodeLength(content.length);
    final result = Uint8List(1 + lengthBytes.length + content.length);
    result[0] = tag;
    result.setRange(1, 1 + lengthBytes.length, lengthBytes);
    result.setRange(1 + lengthBytes.length, result.length, content);
    return result;
  }

  static Uint8List _encodeLength(int length) {
    if (length < 128) {
      return Uint8List.fromList([length]);
    }
    // Long form
    final bytes = <int>[];
    int value = length;
    while (value > 0) {
      bytes.insert(0, value & 0xff);
      value >>= 8;
    }
    return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
  }

  static Uint8List _encodeBigInt(BigInt value) {
    // Convert BigInt to bytes (big-endian, two's complement)
    if (value == BigInt.zero) {
      return Uint8List.fromList([0x00]);
    }

    final bytes = <int>[];
    BigInt v = value;
    while (v > BigInt.zero) {
      bytes.insert(0, (v & BigInt.from(0xff)).toInt());
      v >>= 8;
    }

    // Add leading 0x00 if high bit is set (to ensure positive interpretation)
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes.insert(0, 0x00);
    }

    return Uint8List.fromList(bytes);
  }
}

/// Simple data class to hold parsed RSA key components
class _RsaKeyData {
  final BigInt modulus;
  final BigInt publicExponent;
  final BigInt privateExponent;
  final BigInt p;
  final BigInt q;

  _RsaKeyData({
    required this.modulus,
    required this.publicExponent,
    required this.privateExponent,
    required this.p,
    required this.q,
  });
}

/// Email DNS diagnostics service
///
/// Usage:
/// ```dart
/// final service = EmailDnsService();
/// final report = await service.diagnose('example.com');
/// service.printReport(report);
/// ```
class EmailDnsService {
  /// DKIM selector to check (default: 'geogram')
  final String dkimSelector;

  /// Timeout for DNS queries
  final Duration timeout;

  /// DKIM private key in PEM format (optional - for showing public key in recommendations)
  final String? dkimPrivateKey;

  EmailDnsService({
    this.dkimSelector = 'geogram',
    this.timeout = const Duration(seconds: 10),
    this.dkimPrivateKey,
  });

  /// Run full DNS diagnostics for email
  Future<EmailDnsReport> diagnose(String domain, {String? serverIp}) async {
    final recommendations = <String>[];

    // Get server IP if not provided (uses local interface detection)
    serverIp ??= await _getServerIp(domain);

    // Check if the detected IP is public or private
    final isPrivateIp = serverIp != null && !_isPublicIp(serverIp);

    // Use the IP for recommendations only if it's public
    final publicIp = isPrivateIp ? null : serverIp;

    // Run all checks in parallel
    final results = await Future.wait([
      _checkMx(domain),
      _checkSpf(domain, publicIp),
      _checkDkim(domain),
      _checkDmarc(domain),
      if (publicIp != null) _checkPtr(publicIp, domain),
      _checkSmtp(domain),
    ]);

    final mx = results[0];
    final spf = results[1];
    final dkim = results[2];
    final dmarc = results[3];
    final hasPtr = publicIp != null;
    final ptr = hasPtr ? results[4] : null;
    final smtp = hasPtr ? results[5] : results[4];

    // Collect recommendations
    if (mx?.recommendation != null) recommendations.add(mx!.recommendation!);
    if (spf?.recommendation != null) recommendations.add(spf!.recommendation!);
    if (dkim?.recommendation != null) recommendations.add(dkim!.recommendation!);
    if (dmarc?.recommendation != null) {
      recommendations.add(dmarc!.recommendation!);
    }
    if (ptr?.recommendation != null) recommendations.add(ptr!.recommendation!);
    if (smtp?.recommendation != null) recommendations.add(smtp!.recommendation!);

    final allPassed = (mx?.isOk ?? false) &&
        (spf?.isOk ?? false) &&
        (smtp?.isOk ?? false);

    return EmailDnsReport(
      domain: domain,
      serverIp: serverIp,
      serverIpIsLocalOverride: isPrivateIp,
      timestamp: DateTime.now(),
      mx: mx,
      spf: spf,
      dkim: dkim,
      dmarc: dmarc,
      ptr: ptr,
      smtp: smtp,
      recommendations: recommendations,
      allPassed: allPassed,
    );
  }

  /// Get the server's public IPv4 address
  /// Uses network interface enumeration - no data sent to external services
  Future<String?> _getServerIp(String domain) async {
    final ip = await _primaryIPv4();
    return ip?.address;
  }

  /// Get primary IPv4 address by enumerating network interfaces
  Future<InternetAddress?> _primaryIPv4() async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      // Prefer public IPs over private ones
      InternetAddress? bestPrivate;

      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!_isUsableIPv4(addr)) continue;

          // If it's a public IP, return immediately
          if (_isPublicIp(addr.address)) {
            return addr;
          }

          // Otherwise remember best private IP as fallback
          bestPrivate ??= addr;
        }
      }

      return bestPrivate;
    } catch (_) {
      return null;
    }
  }

  /// Check if an IPv4 address is usable (not loopback, link-local, or any)
  bool _isUsableIPv4(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final s = a.address;

    if (s.startsWith('127.')) return false; // Loopback
    if (s.startsWith('169.254.')) return false; // Link-local (APIPA)
    if (s == '0.0.0.0') return false; // Any

    return true;
  }

  /// Check if an IP address is public (not localhost or private)
  bool _isPublicIp(String ip) {
    if (ip.startsWith('127.') || ip == '::1') return false; // Localhost
    if (ip.startsWith('10.')) return false; // Private Class A
    if (ip.startsWith('172.')) {
      // Private Class B: 172.16.0.0 - 172.31.255.255
      final second = int.tryParse(ip.split('.')[1]) ?? 0;
      if (second >= 16 && second <= 31) return false;
    }
    if (ip.startsWith('192.168.')) return false; // Private Class C
    if (ip.startsWith('169.254.')) return false; // Link-local
    return true;
  }

  /// Check MX records
  Future<DnsCheckResult> _checkMx(String domain) async {
    try {
      final records = await _queryDns(domain, 'MX');

      if (records.isEmpty) {
        return DnsCheckResult(
          recordType: 'MX',
          found: false,
          error: 'No MX record found',
          recommendation: _generateMxRecommendation(domain),
        );
      }

      // Check if domain points to itself (common for small servers)
      final mxValue = records.first;
      return DnsCheckResult(
        recordType: 'MX',
        found: true,
        value: mxValue,
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'MX',
        found: false,
        error: 'DNS query failed: $e',
        recommendation: _generateMxRecommendation(domain),
      );
    }
  }

  /// Check SPF record
  Future<DnsCheckResult> _checkSpf(String domain, String? serverIp) async {
    try {
      final records = await _queryDns(domain, 'TXT');
      final spfRecord = records.firstWhere(
        (r) => r.startsWith('v=spf1'),
        orElse: () => '',
      );

      if (spfRecord.isEmpty) {
        return DnsCheckResult(
          recordType: 'SPF',
          found: false,
          error: 'No SPF record found',
          recommendation: _generateSpfRecommendation(domain, serverIp),
        );
      }

      // Validate SPF record
      String? error;
      if (serverIp != null && !spfRecord.contains(serverIp)) {
        // Check if it has ip4: or includes the domain
        if (!spfRecord.contains('ip4:') &&
            !spfRecord.contains('a') &&
            !spfRecord.contains('mx')) {
          error = 'SPF record may not authorize this server';
        }
      }

      return DnsCheckResult(
        recordType: 'SPF',
        found: true,
        value: spfRecord,
        error: error,
        recommendation: error != null
            ? _generateSpfRecommendation(domain, serverIp)
            : null,
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'SPF',
        found: false,
        error: 'DNS query failed: $e',
        recommendation: _generateSpfRecommendation(domain, serverIp),
      );
    }
  }

  /// Check DKIM record
  Future<DnsCheckResult> _checkDkim(String domain) async {
    try {
      final dkimDomain = '$dkimSelector._domainkey.$domain';
      final records = await _queryDns(dkimDomain, 'TXT');

      if (records.isEmpty) {
        return DnsCheckResult(
          recordType: 'DKIM',
          found: false,
          error: 'No DKIM record found for selector "$dkimSelector"',
          recommendation: _generateDkimRecommendation(domain),
        );
      }

      final dkimRecord = records.first;
      if (!dkimRecord.contains('v=DKIM1') && !dkimRecord.contains('p=')) {
        return DnsCheckResult(
          recordType: 'DKIM',
          found: true,
          value: dkimRecord,
          error: 'Invalid DKIM record format',
          recommendation: _generateDkimRecommendation(domain),
        );
      }

      return DnsCheckResult(
        recordType: 'DKIM',
        found: true,
        value: dkimRecord.length > 80
            ? '${dkimRecord.substring(0, 80)}...'
            : dkimRecord,
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'DKIM',
        found: false,
        error: 'DNS query failed: $e',
        recommendation: _generateDkimRecommendation(domain),
      );
    }
  }

  /// Check DMARC record
  Future<DnsCheckResult> _checkDmarc(String domain) async {
    try {
      final dmarcDomain = '_dmarc.$domain';
      final records = await _queryDns(dmarcDomain, 'TXT');

      if (records.isEmpty) {
        return DnsCheckResult(
          recordType: 'DMARC',
          found: false,
          error: 'No DMARC record found',
          recommendation: _generateDmarcRecommendation(domain),
        );
      }

      final dmarcRecord = records.first;
      if (!dmarcRecord.startsWith('v=DMARC1')) {
        return DnsCheckResult(
          recordType: 'DMARC',
          found: true,
          value: dmarcRecord,
          error: 'Invalid DMARC record format',
          recommendation: _generateDmarcRecommendation(domain),
        );
      }

      return DnsCheckResult(
        recordType: 'DMARC',
        found: true,
        value: dmarcRecord,
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'DMARC',
        found: false,
        error: 'DNS query failed: $e',
        recommendation: _generateDmarcRecommendation(domain),
      );
    }
  }

  /// Check PTR (reverse DNS) record
  Future<DnsCheckResult> _checkPtr(String ip, String domain) async {
    try {
      final result = await InternetAddress(ip).reverse();
      final ptrHost = result.host;

      if (!ptrHost.contains(domain)) {
        return DnsCheckResult(
          recordType: 'PTR',
          found: true,
          value: ptrHost,
          error: 'PTR record does not match domain',
          recommendation: _generatePtrRecommendation(ip, domain),
        );
      }

      return DnsCheckResult(
        recordType: 'PTR',
        found: true,
        value: ptrHost,
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'PTR',
        found: false,
        error: 'Reverse DNS lookup failed: $e',
        recommendation: _generatePtrRecommendation(ip, domain),
      );
    }
  }

  /// Check SMTP connectivity
  Future<DnsCheckResult> _checkSmtp(String domain) async {
    try {
      final socket = await Socket.connect(
        domain,
        25,
        timeout: timeout,
      );

      // Read greeting
      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
          if (buffer.toString().contains('\r\n')) {
            if (!completer.isCompleted) {
              completer.complete(buffer.toString());
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
      );

      final greeting = await completer.future.timeout(timeout);
      await socket.close();

      if (greeting.startsWith('220')) {
        return DnsCheckResult(
          recordType: 'SMTP',
          found: true,
          value: greeting.trim(),
        );
      } else {
        return DnsCheckResult(
          recordType: 'SMTP',
          found: true,
          value: greeting.trim(),
          error: 'Unexpected SMTP response',
        );
      }
    } on SocketException catch (e) {
      String error;
      String? recommendation;

      if (e.osError?.errorCode == 111 || e.message.contains('refused')) {
        error = 'Connection refused - SMTP server not running on port 25';
        recommendation =
            'Start the Geogram station with SMTP enabled, or check firewall settings';
      } else if (e.osError?.errorCode == 113 ||
          e.message.contains('unreachable')) {
        error = 'Host unreachable - check network connectivity';
        recommendation = 'Verify the domain resolves correctly and port 25 is open';
      } else {
        error = 'Connection failed: ${e.message}';
        recommendation = 'Check if port 25 is open and SMTP service is running';
      }

      return DnsCheckResult(
        recordType: 'SMTP',
        found: false,
        error: error,
        recommendation: recommendation,
      );
    } on TimeoutException {
      return DnsCheckResult(
        recordType: 'SMTP',
        found: false,
        error: 'Connection timed out',
        recommendation:
            'Check if port 25 is blocked by firewall or ISP',
      );
    } catch (e) {
      return DnsCheckResult(
        recordType: 'SMTP',
        found: false,
        error: 'Connection failed: $e',
        recommendation: 'Check SMTP server configuration',
      );
    }
  }

  /// Query DNS records using command-line tools (dig/nslookup)
  /// Works on Linux, macOS, and Windows
  Future<List<String>> _queryDns(String domain, String recordType) async {
    return _queryDnsCommandLine(domain, recordType);
  }

  /// Query DNS records using command-line tools (dig/nslookup)
  Future<List<String>> _queryDnsCommandLine(
    String domain,
    String recordType,
  ) async {
    // Try dig with common paths (PATH might be overwritten by environment)
    final digPaths = ['/usr/bin/dig', '/bin/dig', 'dig'];

    for (final digPath in digPaths) {
      try {
        final digResult = await Process.run(
          digPath,
          ['+short', recordType, domain, '@8.8.8.8'], // Use Google DNS for reliability
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

        if (digResult.exitCode == 0) {
          final output = (digResult.stdout as String).trim();
          if (output.isNotEmpty) {
            return output
                .split('\n')
                .map((s) => s.replaceAll('"', '').trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          // dig succeeded but no records - this is a valid result
          return [];
        }
      } catch (_) {
        // Try next path
      }
    }

    // Fallback to nslookup (Windows/Linux/macOS)
    final nslookupPaths = ['/usr/bin/nslookup', '/bin/nslookup', 'nslookup'];

    for (final nsPath in nslookupPaths) {
      try {
        final nsResult = await Process.run(
          nsPath,
          ['-type=$recordType', domain, '8.8.8.8'], // Use Google DNS
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

        if (nsResult.exitCode == 0) {
          final output = nsResult.stdout as String;
          final records = <String>[];

          // Parse nslookup output based on record type
          for (final line in output.split('\n')) {
            if (recordType == 'MX' && line.contains('mail exchanger')) {
              final match = RegExp(r'mail exchanger = (.+)').firstMatch(line);
              if (match != null) records.add(match.group(1)!.trim());
            } else if (recordType == 'TXT' && line.contains('text =')) {
              final match = RegExp(r'text = "(.+)"').firstMatch(line);
              if (match != null) records.add(match.group(1)!);
            } else if (recordType == 'A' && line.contains('Address:')) {
              // Skip the server address line
              if (!line.contains('#')) {
                final match = RegExp(r'Address:\s*(\S+)').firstMatch(line);
                if (match != null) records.add(match.group(1)!.trim());
              }
            }
          }

          return records;
        }
      } catch (_) {
        // Try next path
      }
    }

    return [];
  }

  // Recommendation generators

  String _generateMxRecommendation(String domain) {
    return '''
Add an MX record to your DNS:

  $domain.    IN  MX  10  $domain.

Or if using a mail subdomain:

  $domain.    IN  MX  10  mail.$domain.
  mail.$domain.  IN  A   <YOUR_SERVER_IP>
''';
  }

  String _generateSpfRecommendation(String domain, String? serverIp) {
    final ip = serverIp ?? '<YOUR_SERVER_IP>';
    return '''
Add an SPF record to authorize your server to send email:

  $domain.    IN  TXT  "v=spf1 ip4:$ip mx -all"

Or for a more relaxed policy:

  $domain.    IN  TXT  "v=spf1 ip4:$ip mx ~all"
''';
  }

  String _generateDkimRecommendation(String domain) {
    // Try to derive public key from stored private key
    String? publicKeyBase64;
    if (dkimPrivateKey != null && dkimPrivateKey!.isNotEmpty) {
      publicKeyBase64 = DkimKeyGenerator.derivePublicKeyBase64(dkimPrivateKey!);
    }

    if (publicKeyBase64 != null) {
      // We have the public key - format for DNS TXT record
      // DNS TXT records have 255 char limit per string, so split if needed
      final txtValue = _formatDkimTxtRecord(publicKeyBase64);

      return '''
Add this DKIM TXT record to your DNS:

  $dkimSelector._domainkey.$domain.  IN  TXT  $txtValue

Your DKIM private key is stored in station_config.json.

Note: If your DNS provider has issues with long records, you may need to
enter the value without quotes and let them handle the formatting.
The raw value is: v=DKIM1; k=rsa; p=$publicKeyBase64
''';
    }

    // No private key - prompt to generate one
    return '''
DKIM requires a public/private key pair. Run this command to generate:

  geogram-cli --email-dns

The private key will be saved to your station configuration automatically.
After running, check DNS again to get the record to add.

Note: DKIM is optional but recommended for better deliverability.
''';
  }

  /// Format DKIM record for DNS TXT, splitting into 255-char chunks if needed
  String _formatDkimTxtRecord(String publicKeyBase64) {
    final fullValue = 'v=DKIM1; k=rsa; p=$publicKeyBase64';

    // If short enough, return as single quoted string
    if (fullValue.length <= 255) {
      return '"$fullValue"';
    }

    // Split into 255-char chunks for DNS compatibility
    final chunks = <String>[];
    for (int i = 0; i < fullValue.length; i += 255) {
      final end = (i + 255 < fullValue.length) ? i + 255 : fullValue.length;
      chunks.add('"${fullValue.substring(i, end)}"');
    }

    // Format as multi-line with parentheses for zone file
    return '( ${chunks.join(' ')} )';
  }

  String _generateDmarcRecommendation(String domain) {
    return '''
Add a DMARC record to specify how receivers should handle authentication failures:

  _dmarc.$domain.  IN  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@$domain"

DMARC policies:
  p=none      - Monitor only, no action taken
  p=quarantine - Mark as spam if authentication fails
  p=reject    - Reject email if authentication fails

Start with p=none to monitor, then strengthen as needed.
''';
  }

  String _generatePtrRecommendation(String ip, String domain) {
    return '''
Configure reverse DNS (PTR) record with your hosting provider:

  $ip should resolve to $domain (or mail.$domain)

PTR records are set by your hosting provider, not in your DNS zone.
Contact your VPS/server provider to set up reverse DNS.
''';
  }

  /// Print report to stdout with colors
  void printReport(EmailDnsReport report, {bool useColors = true}) {
    final green = useColors ? '\x1B[32m' : '';
    final red = useColors ? '\x1B[31m' : '';
    final yellow = useColors ? '\x1B[33m' : '';
    final cyan = useColors ? '\x1B[36m' : '';
    final bold = useColors ? '\x1B[1m' : '';
    final reset = useColors ? '\x1B[0m' : '';

    stdout.writeln();
    stdout.writeln('$bold══════════════════════════════════════════════════════════════$reset');
    stdout.writeln('$bold  EMAIL DNS DIAGNOSTICS$reset');
    stdout.writeln('$bold══════════════════════════════════════════════════════════════$reset');
    stdout.writeln();
    stdout.writeln('  Domain:    $cyan${report.domain}$reset');
    if (report.serverIp != null) {
      if (report.serverIpIsLocalOverride) {
        stdout.writeln('  Server IP: $yellow${report.serverIp}$reset $red(PRIVATE - use your public IP in DNS records)$reset');
      } else {
        stdout.writeln('  Server IP: $cyan${report.serverIp}$reset');
      }
    }
    stdout.writeln('  Checked:   ${report.timestamp.toLocal()}');
    stdout.writeln();
    stdout.writeln('$bold──────────────────────────────────────────────────────────────$reset');
    stdout.writeln('$bold  RECORD CHECKS$reset');
    stdout.writeln('$bold──────────────────────────────────────────────────────────────$reset');

    void printCheck(DnsCheckResult? result) {
      if (result == null) return;

      final status = result.isOk
          ? '$green[OK]$reset'
          : result.found
              ? '$yellow[WARN]$reset'
              : '$red[MISSING]$reset';

      stdout.writeln();
      stdout.writeln('  ${result.recordType.padRight(6)} $status');

      if (result.value != null) {
        stdout.writeln('         Value: ${result.value}');
      }
      if (result.error != null) {
        stdout.writeln('         $red${result.error}$reset');
      }
    }

    printCheck(report.mx);
    printCheck(report.spf);
    printCheck(report.dkim);
    printCheck(report.dmarc);
    printCheck(report.ptr);
    printCheck(report.smtp);

    if (report.recommendations.isNotEmpty) {
      stdout.writeln();
      stdout.writeln('$bold──────────────────────────────────────────────────────────────$reset');
      stdout.writeln('$bold  RECOMMENDATIONS$reset');
      stdout.writeln('$bold──────────────────────────────────────────────────────────────$reset');

      for (final rec in report.recommendations) {
        stdout.writeln();
        stdout.writeln('$yellow$rec$reset');
      }
    }

    stdout.writeln();
    stdout.writeln('$bold══════════════════════════════════════════════════════════════$reset');

    if (report.allPassed) {
      stdout.writeln('$green  All essential checks passed! Email should work.$reset');
    } else {
      stdout.writeln('$yellow  Some checks failed. Review recommendations above.$reset');
    }
    stdout.writeln('$bold══════════════════════════════════════════════════════════════$reset');
    stdout.writeln();
  }

  /// Generate DNS zone file snippet
  String generateDnsZone(String domain, String serverIp) {
    // Try to derive public key from stored private key
    String? publicKeyBase64;
    if (dkimPrivateKey != null && dkimPrivateKey!.isNotEmpty) {
      publicKeyBase64 = DkimKeyGenerator.derivePublicKeyBase64(dkimPrivateKey!);
    }

    final dkimLine = publicKeyBase64 != null
        ? '$dkimSelector._domainkey.$domain.  IN  TXT  ${_formatDkimTxtRecord(publicKeyBase64)}'
        : '; $dkimSelector._domainkey.$domain.  IN  TXT  "v=DKIM1; k=rsa; p=<PUBLIC_KEY>"  ; Run --email-dns to generate';

    return '''
; DNS Zone File for $domain - Email Configuration
; Add these records to your DNS provider

; MX Record - Route email to this server
$domain.                IN  MX     10  $domain.

; SPF Record - Authorize this server to send email
$domain.                IN  TXT    "v=spf1 ip4:$serverIp mx -all"

; DMARC Record - Email authentication policy
_dmarc.$domain.         IN  TXT    "v=DMARC1; p=none; rua=mailto:postmaster@$domain"

; DKIM Record - Email signature verification
$dkimLine

; Note: PTR (reverse DNS) must be configured with your hosting provider
''';
  }
}
