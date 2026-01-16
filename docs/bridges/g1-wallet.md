# G1 (Ğ1) Libre Currency Wallet Integration

## Overview

Integrate full G1 (Ğ1) libre currency wallet functionality into Geogram alongside the existing debt ledger wallet. G1 is a cryptocurrency based on Universal Dividend, running on **Duniter v2** (Substrate-based blockchain).

**Target**: Duniter v2 (Substrate) - future-proof implementation that won't require migration.

## Current State

Geogram has an existing **debt ledger wallet** that:
- Uses NOSTR/BIP-340 Schnorr signatures (secp256k1 curve)
- Stores debts as markdown files with cryptographic signature chains
- Supports P2P sync between parties
- Tracks debts, receipts, and balances in multiple fiat currencies

G1/Duniter v2 uses:
- **Ed25519** keypairs (different from NOSTR's secp256k1)
- **Substrate RPC API** for blockchain queries and transactions
- **SCALE codec** for encoding transactions
- Base58 encoded addresses with SS58 format

## Architecture Decision

**Separate G1 identity** from NOSTR identity because:
1. Different key algorithms (Ed25519 vs secp256k1)
2. G1 identity is tied to blockchain certification (Web of Trust)
3. Users may already have existing G1 accounts to import
4. Cleaner separation of concerns

## Dependencies to Add

```yaml
# pubspec.yaml additions
dependencies:
  pinenacl: ^0.6.0             # NaCl crypto (Ed25519 for G1)
  fast_base58: ^0.2.1          # G1 address encoding
  substrate_metadata: ^0.3.0   # Substrate metadata parsing
  polkadart: ^0.4.0            # Dart Substrate client (or durt2)
```

Note: Geogram already has `pointycastle`, `crypto`, `hex`, and `http` which are reusable.

Reference: [Gecko pubspec.yaml](https://git.duniter.org/clients/gecko/-/blob/master/pubspec.yaml)

## Files to Create

### 1. `lib/g1/services/g1_service.dart`
Main G1 service (singleton) handling:
- Key generation/import (Ed25519)
- Balance queries via Substrate RPC
- Transaction creation and submission
- Web of Trust status queries
- UD (Universal Dividend) history

### 2. `lib/g1/services/substrate_client.dart`
Substrate RPC client:
- WebSocket connection to Duniter v2 nodes
- Runtime metadata fetching
- Transaction submission
- Event subscription for confirmations

### 3. `lib/g1/models/g1_account.dart`
Account model:
- Public/private Ed25519 keypair
- SS58 address format
- Certified member status
- Balance in G1 (Ğ1) with UD history

### 4. `lib/g1/models/g1_transaction.dart`
Transaction model:
- Sender/receiver addresses
- Amount in G1 (centiG1 internally)
- Comment (optional, via remark extrinsic)
- Block hash and timestamp
- Transaction status

### 5. `lib/g1/crypto/g1_keypair.dart`
Cryptographic utilities:
- Ed25519 key generation from seed
- Seed phrase (mnemonic) support
- SS58 address encoding/decoding
- Transaction signing

### 6. `lib/pages/g1_wallet_page.dart`
Main G1 wallet UI:
- Balance display (in Ğ1)
- Transaction history
- Send/receive buttons
- QR code for receiving

### 7. `lib/pages/g1_send_page.dart`
Send G1 form:
- Recipient address (scan QR or paste)
- Amount input
- Optional comment
- Confirmation dialog with fee estimate

### 8. `lib/pages/g1_settings_page.dart`
G1 account settings:
- View public address with QR
- Export seed phrase (secure backup)
- Preferred node selection
- Identity/certification status

## Files to Modify

### 1. `lib/pages/wallet_browser_page.dart`
Add tab or toggle between:
- Existing debt ledger view ("Debts")
- New G1 wallet view ("Ğ1")

### 2. `lib/main.dart`
Initialize G1Service lazily when wallet accessed

### 3. `pubspec.yaml`
Add new dependencies

## Implementation Steps

### Phase 1: Core Infrastructure
1. Add dependencies to pubspec.yaml
2. Create `g1_keypair.dart` with Ed25519 key generation
3. Create `substrate_client.dart` with basic RPC
4. Test connection to Duniter v2 testnet node

### Phase 2: Read-Only Features
1. Implement balance query
2. Create `g1_wallet_page.dart` with balance display
3. Add transaction history via RPC
4. Add QR code generation for receiving
5. Wire up to wallet_browser_page tabs

### Phase 3: Transaction Support
1. Implement SCALE encoding for transfer extrinsic
2. Implement transaction signing with Ed25519
3. Create `g1_send_page.dart`
4. Add QR code scanning for recipients
5. Test send on Duniter v2 testnet

### Phase 4: Identity & Polish
1. Query Web of Trust membership status
2. Show member vs simple wallet distinction
3. Display UD (Universal Dividend) claims
4. Add settings page for seed export
5. Import existing Cesium/Gecko wallet

## Key Technical Details

### Substrate RPC Calls

```dart
// Balance query
final balance = await client.call('state_call', [
  'AccountApi_balance',
  accountId.toHex(),
]);

// Submit transaction
final hash = await client.call('author_submitExtrinsic', [
  signedExtrinsic.toHex(),
]);

// Subscribe to finalization
client.subscribe('chain_subscribeFinalizedHeads', [], (header) {
  // Check if our tx is in this block
});
```

### Ed25519 Key Generation

```dart
import 'package:pinenacl/ed25519.dart';

// From seed (32 bytes)
final seed = SecureRandom().nextBytes(32);
final signingKey = SigningKey.fromSeed(seed);
final publicKey = signingKey.verifyKey;

// SS58 address encoding
final address = ss58Encode(publicKey.asTypedList, prefix: 42); // Duniter prefix
```

### SS58 Address Format

```dart
// Duniter uses SS58 with network prefix 42
// Format: base58(prefix + pubkey + checksum)
String ss58Encode(Uint8List pubkey, {int prefix = 42}) {
  final payload = [prefix, ...pubkey];
  final checksum = blake2b512('SS58PRE' + payload).sublist(0, 2);
  return base58Encode([...payload, ...checksum]);
}
```

### Node Endpoints

- **Duniter v2 Main net**: `wss://gdev.p2p.legal:443/ws` (example)
- **Duniter v2 Test net**: `wss://gdev.coinduf.eu:443/ws`

Check [Duniter v2 documentation](https://duniter.org/wiki/duniter-v2/) for current endpoints.

## Verification

1. Generate new G1 keypair, verify SS58 address format
2. Connect to Duniter v2 testnet node
3. Query balance for known address
4. Display transaction history
5. Successfully send Ğ1 on testnet
6. Import existing Cesium wallet seed and verify balance matches

## Risks & Considerations

1. **Duniter v2 stability**: v2 is still under development, API may change
2. **Network dependency**: G1 features require internet (unlike debt ledger)
3. **Key security**: Ed25519 seed needs secure storage (consider Android Keystore)
4. **Identity certification**: Full member benefits require in-person Web of Trust certification
5. **Transaction fees**: Duniter v2 has minimal fees, need to handle edge cases

## Resources

- [Duniter GitLab](https://git.duniter.org/)
- [Gecko Flutter wallet](https://git.duniter.org/clients/gecko)
- [Duniter v2 documentation](https://duniter.org/wiki/duniter-v2/)
- [Duniter Forum](https://forum.duniter.org/)
- [Substrate documentation](https://docs.substrate.io/)
