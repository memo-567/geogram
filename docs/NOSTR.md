# NOSTR Integration

**Version**: 1.1
**Last Updated**: 2026-01-13
**Status**: Active

## Overview

Geogram uses NOSTR for identity, cryptographic signatures, and decentralized communication. All users have a NOSTR key pair (npub/nsec) that provides cryptographic identity.

## Supported NIPs

| NIP | Name | Implementation |
|-----|------|----------------|
| NIP-01 | Basic protocol | Core events, signatures, relay communication |
| NIP-04 | Encrypted DMs | Via browser extension (NIP-07) |
| NIP-05 | DNS Identity | Station serves `/.well-known/nostr.json` |
| NIP-07 | Browser Extension | Alby, nos2x support for web signing |
| NIP-25 | Reactions | Blog post likes using kind 7 events |
| NIP-78 | App-specific Data | Alert sharing using kind 30078 |

## NIP-05: Identity Verification

NIP-05 enables human-readable NOSTR identifiers like `alice@p2p.radio` that can be verified against a user's npub.

### Server Endpoint

```
GET /.well-known/nostr.json
GET /.well-known/nostr.json?name=alice
```

### Response Format

```json
{
  "names": {
    "alice": "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef12345678"
  },
  "relays": {
    "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef12345678": [
      "wss://p2p.radio"
    ]
  }
}
```

Note: Public keys are returned in hex format (64 characters), not bech32 npub format.

### Nickname Registration

When a user connects to a station server, their identity is automatically registered:

1. **Callsign** is always registered (e.g., `x1abc@p2p.radio`)
2. **Nickname** is also registered if different from callsign (e.g., `alice@p2p.radio`)

Both identifiers resolve to the same npub.

### Anti-Spoofing Protection

- **12-month reservation**: First user to register a nickname owns it for 12 months
- **Automatic renewal**: Each reconnection renews the 12-month period
- **Expiration**: After 12 months without activity, registration expires and nickname can be claimed by anyone
- **Reserved nicknames**: Common names like `admin`, `support`, `security` are reserved for station owners only

#### Reserved Nicknames

```
admin, mail, support, abuse, security, noreply,
postmaster, webmaster, hostmaster, root, info, help
```

### Connection Security

When a client connects to a station, the following security checks are enforced:

1. **npub Required**: Clients must provide a valid npub in the HELLO message
2. **Callsign Binding**: Once a callsign is registered to an npub, only that npub can use it
3. **Nickname Protection**: Custom nicknames are also bound to the registering npub
4. **Connection Rejection**: Attempts to use another user's callsign/nickname result in connection rejection

This prevents:
- **Email impersonation**: Sending emails as someone else's address (e.g., `alice@p2p.radio`)
- **Email interception**: Receiving emails meant for someone else
- **Identity spoofing**: Using another user's identity in chat and other features

#### Error Codes

When a connection is rejected due to identity collision:

| Error | Description |
|-------|-------------|
| `callsign_npub_mismatch` | Callsign is registered to a different npub |
| `nickname_npub_mismatch` | Nickname is registered to a different npub |

#### Example Rejection Response

```json
{
  "type": "hello_ack",
  "success": false,
  "error": "callsign_npub_mismatch",
  "message": "Callsign \"alice\" is registered to a different identity",
  "station_id": "X3QVZ4"
}
```

If you receive this error, you should:
- Use a different callsign/nickname
- Recover your original keypair if this is your account

### Storage

Registrations are persisted in `{profile_directory}/nip05_registry.json`:

```json
{
  "registrations": [
    {
      "nickname": "alice",
      "npub": "npub1...",
      "registeredAt": "2025-01-15T10:30:45.123Z",
      "expiresAt": "2026-01-15T10:30:45.123Z"
    }
  ]
}
```

### Client Resolution

Geogram clients can verify NIP-05 identifiers from external domains:

```dart
final resolver = Nip05ResolverService();

// Resolve identifier to get pubkey and relays
final identity = await resolver.resolve('alice@example.com');
if (identity != null) {
  print('Hex pubkey: ${identity.hexPubkey}');
  print('Npub: ${identity.npub}');
  print('Relays: ${identity.relays}');
}

// Verify a contact's NIP-05 claim
final isValid = await resolver.verify('alice@example.com', contact.npub);
```

Results are cached for 1 hour to reduce network requests.

## NIP-01: Core Protocol

### Event Structure

All NOSTR events follow the standard structure:

```json
{
  "id": "event_id_hash",
  "pubkey": "hex_public_key",
  "created_at": 1234567890,
  "kind": 1,
  "tags": [
    ["p", "pubkey"],
    ["e", "event_id"]
  ],
  "content": "message content",
  "sig": "schnorr_signature"
}
```

### Supported Event Kinds

| Kind | Name | Usage |
|------|------|-------|
| 0 | Set Metadata | Profile information |
| 1 | Text Note | Basic messages |
| 3 | Contacts | Contact list |
| 7 | Reaction | Blog likes (NIP-25) |
| 30078 | App Data | Alert sharing (NIP-78) |

### Cryptography

- **Curve**: secp256k1
- **Signature**: BIP-340 Schnorr (64 bytes)
- **Key encoding**: Bech32 (npub1... / nsec1...)
- **Event ID**: SHA-256 of serialized event

## NIP-07: Browser Extension

Web clients can sign events using browser extensions like Alby or nos2x.

### Supported Operations

```javascript
// Get public key
const pubkey = await window.nostr.getPublicKey();

// Sign event
const signedEvent = await window.nostr.signEvent(event);

// Get relays
const relays = await window.nostr.getRelays();

// Encrypt (NIP-04)
const ciphertext = await window.nostr.nip04.encrypt(pubkey, plaintext);

// Decrypt (NIP-04)
const plaintext = await window.nostr.nip04.decrypt(pubkey, ciphertext);
```

## NIP-25: Reactions

Blog posts can receive emoji reactions using kind 7 events.

### Reaction Event

```json
{
  "kind": 7,
  "tags": [
    ["p", "author_pubkey"],
    ["e", "post_id"],
    ["type", "likes"]
  ],
  "content": "like"
}
```

### Web Likes

Browser users with NOSTR extensions can like blog posts:

1. Page detects `window.nostr` extension
2. Like button appears
3. User clicks → extension prompts for signature
4. Signed event sent to blog API
5. Like persisted in `feedback/likes.txt`

## NIP-78: Application Data

Alert sharing uses kind 30078 (parameterized replaceable events).

### Alert Event

```json
{
  "kind": 30078,
  "tags": [
    ["d", "folder_name"],
    ["g", "38.7223,-9.1393"],
    ["t", "alert"],
    ["severity", "high"],
    ["status", "active"],
    ["type", "weather"]
  ],
  "content": "Alert description..."
}
```

## Key Management

### Callsign Format

- **Clients**: `X1` + first 4 chars after `npub1` (e.g., `X1A8CF`)
- **Stations**: `X3` + first 4 chars after `npub1` (e.g., `X3B7DE`)

### Key Generation

```dart
final keys = NostrKeyGenerator.generateKeyPair();
print('npub: ${keys.npub}');
print('nsec: ${keys.nsec}');
print('callsign: ${keys.callsign}');
```

### Key Validation

```dart
final isValidNpub = NostrKeyGenerator.isValidNpub('npub1...');
final isValidNsec = NostrKeyGenerator.isValidNsec('nsec1...');
```

## Related Files

| File | Purpose |
|------|---------|
| `lib/util/nostr_event.dart` | NIP-01 event implementation |
| `lib/util/nostr_crypto.dart` | Cryptography (BIP-340 Schnorr) |
| `lib/util/nostr_key_generator.dart` | Key generation and validation |
| `lib/services/nip05_registry_service.dart` | NIP-05 server (registration) |
| `lib/services/nip05_resolver_service.dart` | NIP-05 client (verification) |
| `lib/services/signing_service.dart` | Unified signing interface |
| `lib/platform/nostr_extension_web.dart` | NIP-07 browser extension |

## References

- [NIP-01: Basic Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-04: Encrypted DMs](https://github.com/nostr-protocol/nips/blob/master/04.md)
- [NIP-05: DNS Identity](https://github.com/nostr-protocol/nips/blob/master/05.md)
- [NIP-07: Browser Extension](https://github.com/nostr-protocol/nips/blob/master/07.md)
- [NIP-25: Reactions](https://github.com/nostr-protocol/nips/blob/master/25.md)
- [NIP-78: App Data](https://github.com/nostr-protocol/nips/blob/master/78.md)
