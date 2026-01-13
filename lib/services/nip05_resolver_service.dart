/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * NIP-05 Resolver Service - Resolves and verifies NIP-05 identifiers
 * from external domains (client-side verification)
 */

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/nostr_crypto.dart';
import '../util/nostr_key_generator.dart';

/// A resolved NIP-05 identity
class Nip05ResolvedIdentity {
  final String identifier;
  final String hexPubkey;
  final List<String> relays;
  final DateTime resolvedAt;

  Nip05ResolvedIdentity({
    required this.identifier,
    required this.hexPubkey,
    required this.relays,
    required this.resolvedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(resolvedAt) > Nip05ResolverService.cacheTtl;

  /// Get the npub (bech32 encoded) from hex pubkey
  String get npub => NostrCrypto.encodeNpub(hexPubkey);

  Map<String, dynamic> toJson() => {
        'identifier': identifier,
        'hexPubkey': hexPubkey,
        'relays': relays,
        'resolvedAt': resolvedAt.toIso8601String(),
      };
}

/// Service for resolving NIP-05 identifiers from external domains
class Nip05ResolverService {
  static final Nip05ResolverService _instance = Nip05ResolverService._();
  factory Nip05ResolverService() => _instance;
  Nip05ResolverService._();

  // Cache resolved identities with TTL
  final Map<String, Nip05ResolvedIdentity> _cache = {};
  static const cacheTtl = Duration(hours: 1);

  /// Resolve a NIP-05 identifier (e.g., "alice@example.com")
  /// Returns the resolved identity if valid, null if not found/invalid
  Future<Nip05ResolvedIdentity?> resolve(String identifier) async {
    // Check cache first
    final cached = _cache[identifier.toLowerCase()];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    // Parse identifier: local-part@domain
    final parts = identifier.split('@');
    if (parts.length != 2) return null;

    final localPart = parts[0].toLowerCase();
    final domain = parts[1].toLowerCase();

    // Validate domain (basic check)
    if (domain.isEmpty || !domain.contains('.')) return null;

    // Fetch from domain
    final url = 'https://$domain/.well-known/nostr.json?name=$localPart';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;
      if (names == null) return null;

      final hexPubkey = names[localPart] as String?;
      if (hexPubkey == null || hexPubkey.length != 64) return null;

      // Get optional relays
      final relays = <String>[];
      final relaysMap = json['relays'] as Map<String, dynamic>?;
      if (relaysMap != null && relaysMap[hexPubkey] != null) {
        final relayList = relaysMap[hexPubkey] as List?;
        if (relayList != null) {
          relays.addAll(relayList.cast<String>());
        }
      }

      final resolved = Nip05ResolvedIdentity(
        identifier: identifier,
        hexPubkey: hexPubkey,
        relays: relays,
        resolvedAt: DateTime.now(),
      );

      _cache[identifier.toLowerCase()] = resolved;
      return resolved;
    } catch (e) {
      return null;
    }
  }

  /// Verify that an npub matches a NIP-05 identifier
  Future<bool> verify(String identifier, String npub) async {
    final resolved = await resolve(identifier);
    if (resolved == null) return false;

    final expectedHex = NostrKeyGenerator.getPublicKeyHex(npub);
    return expectedHex != null && resolved.hexPubkey == expectedHex;
  }

  /// Clear the cache (useful for testing or forced refresh)
  void clearCache() => _cache.clear();

  /// Get cached identity without network request
  Nip05ResolvedIdentity? getCached(String identifier) {
    final cached = _cache[identifier.toLowerCase()];
    if (cached != null && !cached.isExpired) {
      return cached;
    }
    return null;
  }
}
