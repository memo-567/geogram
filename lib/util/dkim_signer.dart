/*
 * DKIM Signer - Signs emails with DKIM (DomainKeys Identified Mail)
 *
 * Implements RFC 6376 for email authentication via cryptographic signatures.
 * Uses RSA-SHA256 with relaxed canonicalization.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// DKIM Signer for email authentication
class DkimSigner {
  final String domain;
  final String selector;
  final RSAPrivateKey _privateKey;

  DkimSigner({
    required this.domain,
    required this.selector,
    required String privateKeyPem,
  }) : _privateKey = _parsePrivateKey(privateKeyPem);

  /// Parse PEM-encoded RSA private key
  static RSAPrivateKey _parsePrivateKey(String pem) {
    // Remove PEM headers and decode base64
    final lines = pem
        .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
        .replaceAll('-----END RSA PRIVATE KEY-----', '')
        .replaceAll('-----BEGIN PRIVATE KEY-----', '')
        .replaceAll('-----END PRIVATE KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');

    final bytes = base64Decode(lines);

    // Parse ASN.1 DER structure
    return _parseRsaPrivateKeyDer(bytes);
  }

  /// Parse DER-encoded RSA private key (PKCS#1 format)
  static RSAPrivateKey _parseRsaPrivateKeyDer(Uint8List bytes) {
    // Simple ASN.1 parser for RSA private key
    int pos = 0;

    // Helper to read ASN.1 length
    int readLength() {
      int length = bytes[pos++];
      if (length & 0x80 != 0) {
        int numBytes = length & 0x7f;
        length = 0;
        for (int i = 0; i < numBytes; i++) {
          length = (length << 8) | bytes[pos++];
        }
      }
      return length;
    }

    // Helper to read ASN.1 integer
    BigInt readInteger() {
      if (bytes[pos++] != 0x02) {
        throw FormatException('Expected INTEGER tag');
      }
      int length = readLength();
      final intBytes = bytes.sublist(pos, pos + length);
      pos += length;

      // Convert to BigInt (handle leading zero for positive numbers)
      BigInt value = BigInt.zero;
      for (final byte in intBytes) {
        value = (value << 8) | BigInt.from(byte);
      }
      return value;
    }

    // Check for SEQUENCE tag
    if (bytes[pos++] != 0x30) {
      throw FormatException('Expected SEQUENCE tag');
    }
    readLength(); // Skip sequence length

    // Check if this is PKCS#8 format (has algorithm identifier)
    if (bytes[pos] == 0x02) {
      // PKCS#1 format - read directly
      final version = readInteger();
      if (version != BigInt.zero) {
        throw FormatException('Unsupported RSA key version');
      }

      final n = readInteger(); // modulus
      readInteger(); // public exponent (not needed for signing)
      final d = readInteger(); // private exponent
      final p = readInteger(); // prime1
      final q = readInteger(); // prime2
      readInteger(); // exponent1 (d mod p-1) - not needed
      readInteger(); // exponent2 (d mod q-1) - not needed
      readInteger(); // coefficient (q^-1 mod p) - not needed

      return RSAPrivateKey(n, d, p, q);
    } else {
      // PKCS#8 format - skip algorithm identifier
      // INTEGER (version)
      if (bytes[pos++] != 0x02) {
        throw FormatException('Expected version INTEGER');
      }
      int vlen = readLength();
      pos += vlen;

      // SEQUENCE (algorithm identifier)
      if (bytes[pos++] != 0x30) {
        throw FormatException('Expected algorithm SEQUENCE');
      }
      int alen = readLength();
      pos += alen;

      // OCTET STRING (private key)
      if (bytes[pos++] != 0x04) {
        throw FormatException('Expected OCTET STRING');
      }
      readLength();

      // Now parse the inner PKCS#1 structure
      if (bytes[pos++] != 0x30) {
        throw FormatException('Expected inner SEQUENCE');
      }
      readLength();

      final version = readInteger();
      if (version != BigInt.zero) {
        throw FormatException('Unsupported RSA key version');
      }

      final n = readInteger();
      readInteger(); // public exponent (not needed for signing)
      final d = readInteger();
      final p = readInteger();
      final q = readInteger();

      return RSAPrivateKey(n, d, p, q);
    }
  }

  /// Sign an email and return the DKIM-Signature header value
  String sign({
    required String from,
    required String to,
    required String subject,
    required String date,
    required String messageId,
    required String body,
    Map<String, String>? extraHeaders,
  }) {
    // Headers to sign (order matters)
    final headersToSign = ['from', 'to', 'subject', 'date', 'message-id'];

    // Build headers map
    final headers = <String, String>{
      'from': from,
      'to': to,
      'subject': subject,
      'date': date,
      'message-id': messageId,
    };
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
      headersToSign.addAll(extraHeaders.keys.map((k) => k.toLowerCase()));
    }

    // Canonicalize body (relaxed)
    final canonBody = _canonicalizeBodyRelaxed(body);

    // Hash body
    final bodyHash = sha256.convert(utf8.encode(canonBody));
    final bodyHashB64 = base64Encode(bodyHash.bytes);

    // Build DKIM-Signature header (without b= value)
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dkimHeader = 'v=1; a=rsa-sha256; c=relaxed/relaxed; '
        'd=$domain; s=$selector; t=$timestamp; '
        'h=${headersToSign.join(':')}; '
        'bh=$bodyHashB64; '
        'b=';

    // Canonicalize headers (relaxed) including DKIM-Signature
    final canonHeaders = _canonicalizeHeadersRelaxed(headers, headersToSign);
    final dkimHeaderCanon = _canonicalizeHeaderRelaxed('dkim-signature', dkimHeader);

    // Data to sign: canonicalized headers + DKIM-Signature header (without trailing CRLF)
    final dataToSign = '$canonHeaders$dkimHeaderCanon';

    // Sign with RSA-SHA256
    final signature = _rsaSign(utf8.encode(dataToSign));
    final signatureB64 = base64Encode(signature);

    // Return complete DKIM-Signature header value
    return '$dkimHeader$signatureB64';
  }

  /// Canonicalize body using relaxed algorithm (RFC 6376 Section 3.4.4)
  String _canonicalizeBodyRelaxed(String body) {
    // 1. Reduce all whitespace sequences to single space
    // 2. Remove trailing whitespace from lines
    // 3. Remove empty lines at end
    // 4. Ensure body ends with CRLF

    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final canonLines = <String>[];

    for (var line in lines) {
      // Reduce whitespace sequences to single space
      line = line.replaceAll(RegExp(r'[ \t]+'), ' ');
      // Remove trailing whitespace
      line = line.trimRight();
      canonLines.add(line);
    }

    // Remove empty lines at end
    while (canonLines.isNotEmpty && canonLines.last.isEmpty) {
      canonLines.removeLast();
    }

    // Join with CRLF and ensure trailing CRLF
    if (canonLines.isEmpty) {
      return '\r\n';
    }
    return '${canonLines.join('\r\n')}\r\n';
  }

  /// Canonicalize headers using relaxed algorithm (RFC 6376 Section 3.4.2)
  String _canonicalizeHeadersRelaxed(
      Map<String, String> headers, List<String> order) {
    final buffer = StringBuffer();

    for (final name in order) {
      final value = headers[name] ?? headers[name.toLowerCase()];
      if (value != null) {
        buffer.write(_canonicalizeHeaderRelaxed(name, value));
        buffer.write('\r\n');
      }
    }

    return buffer.toString();
  }

  /// Canonicalize a single header (relaxed)
  String _canonicalizeHeaderRelaxed(String name, String value) {
    // Convert header name to lowercase
    final canonName = name.toLowerCase();

    // Unfold header value and reduce whitespace
    var canonValue = value
        .replaceAll(RegExp(r'\r?\n[ \t]+'), ' ') // Unfold
        .replaceAll(RegExp(r'[ \t]+'), ' ') // Reduce whitespace
        .trim();

    return '$canonName:$canonValue';
  }

  /// Sign data with RSA-SHA256
  Uint8List _rsaSign(List<int> data) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');

    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(_privateKey));

    return signer.generateSignature(Uint8List.fromList(data)).bytes;
  }
}
