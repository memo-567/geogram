# Wallet Format Specification

**Version**: 1.0
**Last Updated**: 2026-01-02
**Status**: Draft

## Table of Contents

- [Overview](#overview)
- [File Organization](#file-organization)
- [Ledger Format](#ledger-format)
- [Entry Types](#entry-types)
- [Currencies](#currencies)
- [Debt Lifecycle](#debt-lifecycle)
- [Signature Process](#signature-process)
- [P2P Synchronization](#p2p-synchronization)
- [API Endpoints](#api-endpoints)
- [Validation Rules](#validation-rules)
- [Security Considerations](#security-considerations)
- [Legal Compliance](#legal-compliance)

## Overview

The Wallet app tracks debts between parties using NOSTR-signed receipts. Each debt is stored as a single markdown file that acts as an append-only ledger. The file format reuses the chat message format for consistency and code reuse.

### Key Features

- **Debt Tracking**: Track money or time owed to/from others
- **Multi-Currency**: Major world currencies + time (stored in minutes)
- **NOSTR Signatures**: BIP-340 Schnorr signatures for cryptographic verification
- **Witnesses**: Optional third-party witnesses can sign the initial agreement
- **Incremental Ledger**: New entries are appended, never modified
- **Signature Chain**: Each entry signs everything above it (anti-tampering)
- **Party Copies**: Both parties + witnesses maintain identical copies
- **Legal Terms**: Default terms and conditions ensure US and EU legal compliance

## File Organization

### Directory Structure

```
wallet/
├── metadata.json                    # Collection metadata
├── extra/
│   └── security.json                # Permissions
├── requests/                        # Incoming P2P sync requests
│   └── req_20260101_abc123.md       # Pending approval request
└── debts/                           # User-organized folders
    ├── Personal/                    # User-created folder
    │   ├── debt_20260101_abc123.md  # Debt ledger file
    │   └── media/
    │       └── abc123_photo1.jpg
    ├── Business/                    # Another user folder
    │   └── debt_20260102_def456.md
    └── debt_20260103_xyz789.md      # Can be at root level
```

### File Naming Convention

- **Pattern**: `debt_YYYYMMDD_randomid.md`
- **Examples**:
  - `debt_20260101_abc123.md`
  - `debt_20260215_x7f9k2.md`
- **Location**: Any folder within `debts/` directory
- **Moving**: Users can freely move files between folders

### Metadata File

The `metadata.json` file defines collection properties:

```json
{
  "type": "wallet",
  "name": "My Wallet",
  "description": "Personal debt tracking",
  "created_at": "2026-01-01T00:00:00Z"
}
```

## Ledger Format

Each debt is stored as a single markdown file using the same format as chat messages.

### Basic Structure

```markdown
# debt_id: Description

> YYYY-MM-DD HH:MM_ss -- CALLSIGN
--> type: entry_type
--> metadata_key: metadata_value
Content text here.
--> npub: npub1...
--> signature: hex_signature
```

### Header

**Format**: `# debt_id: Description`

- **debt_id**: Unique identifier (e.g., `debt_20260101_abc123`)
- **Description**: Human-readable title for the debt
- **Required**: Yes (first line of file)

**Example**:
```markdown
# debt_20260101_abc123: Loan for car repair
```

### Entry Block

Each entry follows the chat message format:

```markdown
> 2026-01-01 10:00_00 -- X1ABCD
--> type: create
--> status: pending
--> creditor: X1ABCD
--> creditor_npub: npub1abc...
--> debtor: Y2EFGH
--> debtor_npub: npub1def...
--> amount: 100.00
--> currency: EUR
I am lending 100 EUR to Bob for car repair.
--> npub: npub1abc...
--> signature: 3a4f8c92...
```

**Components**:
- `>` - Entry start indicator
- `YYYY-MM-DD HH:MM_ss` - Timestamp (zero-padded)
- ` -- ` - Separator
- `CALLSIGN` - Author's callsign
- `--> key: value` - Metadata fields
- Content text - Free-form description
- `npub` and `signature` - Must be last two fields

## Entry Types

### create

Initial debt creation by either party.

**Required Metadata**:
- `type: create`
- `status: pending`
- `creditor` / `creditor_npub` / `creditor_name`
- `debtor` / `debtor_npub` / `debtor_name`
- `amount` - Original amount
- `currency` - Currency code

**Optional Metadata**:
- `due_date` - Payment deadline (YYYY-MM-DD)
- `terms` - Payment terms description
- `file` / `sha1` - Attached photo with hash

**Example**:
```markdown
> 2026-01-01 10:00_00 -- X1ABCD
--> type: create
--> status: pending
--> creditor: X1ABCD
--> creditor_npub: npub1abc...
--> creditor_name: Alice
--> debtor: Y2EFGH
--> debtor_npub: npub1def...
--> debtor_name: Bob
--> amount: 100.00
--> currency: EUR
--> due_date: 2026-06-01
--> terms: To be repaid in 3 monthly installments
I am lending 100 EUR to Bob for car repair.
--> npub: npub1abc...
--> signature: 3a4f8c92...
```

### confirm

Counterparty confirms and accepts the debt.

**Required Metadata**:
- `type: confirm`
- `status: open`

**Example**:
```markdown
> 2026-01-01 10:15_00 -- Y2EFGH
--> type: confirm
--> status: open
I acknowledge this debt and agree to the terms.
--> npub: npub1def...
--> signature: 5e1a9c6f...
```

### witness

Third-party witness signs the agreement.

**Required Metadata**:
- `type: witness`

**Example**:
```markdown
> 2026-01-01 10:20_00 -- Z3IJKL
--> type: witness
I witness this agreement between Alice and Bob.
--> npub: npub1ghi...
--> signature: 9d6c3f0b...
```

### payment

Records a payment made by the debtor.

**Required Metadata**:
- `type: payment`
- `amount` - Payment amount
- `currency` - Currency code
- `balance` - Remaining balance after payment

**Optional Metadata**:
- `method` - Payment method (cash, bank_transfer, etc.)
- `file` / `sha1` - Receipt photo

**Example**:
```markdown
> 2026-02-01 14:00_00 -- Y2EFGH
--> type: payment
--> amount: 25.00
--> currency: EUR
--> balance: 75.00
--> method: cash
--> file: def456_receipt.jpg
--> sha1: b94a8fe5...
First installment paid.
--> npub: npub1def...
--> signature: 2b8e7a5c...
```

### confirm_payment

Creditor confirms receiving a payment.

**Required Metadata**:
- `type: confirm_payment`

**Example**:
```markdown
> 2026-02-01 14:05_00 -- X1ABCD
--> type: confirm_payment
I confirm receiving 25 EUR payment.
--> npub: npub1abc...
--> signature: 4f1d9e6b...
```

### work_session

Records time worked (for time-based debts).

**Required Metadata**:
- `type: work_session`
- `duration` - Duration in **minutes**

**Optional Metadata**:
- `description` - Work description
- `location` - Where work was performed

**Example**:
```markdown
> 2026-01-15 17:00_00 -- Y2EFGH
--> type: work_session
--> duration: 480
--> description: Garden work - planting and weeding
--> location: Home garden
8 hours of garden work completed today.
--> npub: npub1def...
--> signature: 7e3c9f6b...
```

### confirm_session

Creditor confirms a work session.

**Required Metadata**:
- `type: confirm_session`
- `balance` - Remaining time balance in minutes

**Example**:
```markdown
> 2026-01-15 18:00_00 -- X1ABCD
--> type: confirm_session
--> balance: 480
I confirm 8 hours of work performed.
--> npub: npub1abc...
--> signature: 1a4b9c8e...
```

### status_change

Changes the overall debt status.

**Required Metadata**:
- `type: status_change`
- `status` - New status value

**Note**: Status changes to `paid`, `expired`, or `retired` require entries from both parties.

**Example**:
```markdown
> 2026-06-01 12:30_00 -- X1ABCD
--> type: status_change
--> status: paid
Debt fully settled. Thank you!
--> npub: npub1abc...
--> signature: 6f2b8d4a...
```

### note

Adds a general note or comment.

**Required Metadata**:
- `type: note`

**Example**:
```markdown
> 2026-03-15 09:00_00 -- Y2EFGH
--> type: note
Reminder: Next payment due April 1st.
--> npub: npub1def...
--> signature: 9a8b7c6d...
```

### transfer

Transfers part of a debt to another creditor. Used when the creditor wants to assign part of what they're owed to someone else.

**Scenario**: Person A owes Person B 50 EUR. Person B owes Person C 10 EUR. Person B can transfer 10 EUR of A's debt to C. Result: A now owes B 40 EUR and owes C 10 EUR directly.

**Required Metadata**:
- `type: transfer`
- `amount` - Amount being transferred
- `currency` - Currency code
- `balance` - Remaining balance after transfer
- `new_creditor` - New creditor callsign
- `new_creditor_npub` - New creditor's public key
- `target_debt_id` - ID of the new debt created

**Optional Metadata**:
- `new_creditor_name` - New creditor's display name

**Example**:
```markdown
> 2026-03-01 14:00_00 -- X1ABCD
--> type: transfer
--> amount: 10.00
--> currency: EUR
--> balance: 40.00
--> new_creditor: Z3IJKL
--> new_creditor_npub: npub1ghi...
--> new_creditor_name: Carol
--> target_debt_id: debt_20260301_xyz789
Transferring 10 EUR of this debt to Carol.
--> npub: npub1abc...
--> signature: 7c8d9e0f...
```

### transfer_receive

Initial entry in a debt created from a transfer. This is the first entry in the new debt ledger.

**Required Metadata**:
- `type: transfer_receive`
- `status: pending`
- `creditor` / `creditor_npub` - New creditor (recipient of transfer)
- `debtor` / `debtor_npub` - Original debtor
- `amount` - Transferred amount
- `currency` - Currency code
- `source_debt_id` - Original debt ID
- `original_creditor` / `original_creditor_npub` - Who transferred the debt

**Example**:
```markdown
> 2026-03-01 14:00_00 -- X1ABCD
--> type: transfer_receive
--> status: pending
--> creditor: Z3IJKL
--> creditor_npub: npub1ghi...
--> creditor_name: Carol
--> debtor: Y2EFGH
--> debtor_npub: npub1def...
--> debtor_name: Bob
--> amount: 10.00
--> currency: EUR
--> source_debt_id: debt_20260101_abc123
--> original_creditor: X1ABCD
--> original_creditor_npub: npub1abc...
Debt transferred from Alice.
--> npub: npub1abc...
--> signature: 1a2b3c4d...
```

### transfer_payment

Records that a debt was paid via receiving a transferred debt instead of cash.

**Required Metadata**:
- `type: transfer_payment`
- `amount` - Amount settled
- `currency` - Currency code
- `balance` - Remaining balance
- `transfer_debt_id` - ID of the debt received as payment
- `method: debt_transfer`

**Optional Metadata**:
- `status: paid` - If balance reaches zero

**Example**:
```markdown
> 2026-03-01 14:05_00 -- Z3IJKL
--> type: transfer_payment
--> amount: 10.00
--> currency: EUR
--> balance: 0.00
--> transfer_debt_id: debt_20260301_xyz789
--> method: debt_transfer
--> status: paid
Debt settled by receiving transfer from Alice.
--> npub: npub1ghi...
--> signature: 5e6f7g8h...
```

## Debt Transfer Flow

The complete flow for transferring debt:

```
Initial State:
- Debt 1: A owes B 50 EUR
- Debt 2: B owes C 10 EUR

Step 1: B transfers 10 EUR from Debt 1 to C
- Debt 1 gets "transfer" entry (balance: 40 EUR)
- New Debt 3 created with "transfer_receive" entry (A owes C 10 EUR)

Step 2: Debt 2 is settled
- Debt 2 gets "transfer_payment" entry (balance: 0, status: paid)

Step 3: C confirms the transfer
- Debt 3 gets "confirm" entry from C (status: open)

Step 4: A is notified
- A can see they now owe C 10 EUR
- Original debt (A→B) shows reduced balance

Final State:
- Debt 1: A owes B 40 EUR (reduced)
- Debt 2: B owes C 0 EUR (paid via transfer)
- Debt 3: A owes C 10 EUR (new, from transfer)
```

**Signature Requirements**:
- `transfer`: Signed by original creditor (B)
- `transfer_receive`: Signed by original creditor (B) who initiates
- `transfer_payment`: Signed by the creditor receiving the transfer (C)
- `confirm`: Signed by new creditor (C) to accept the transferred debt

## Currencies

### Monetary Currencies

Listed in priority order for UI display:

| Code | Name | Symbol |
|------|------|--------|
| EUR | Euro | € |
| USD | US Dollar | $ |
| GBP | British Pound | £ |
| CHF | Swiss Franc | CHF |
| JPY | Japanese Yen | ¥ |
| CNY | Chinese Yuan | ¥ |
| CAD | Canadian Dollar | C$ |
| AUD | Australian Dollar | A$ |
| BRL | Brazilian Real | R$ |
| MXN | Mexican Peso | MX$ |
| INR | Indian Rupee | ₹ |
| RUB | Russian Ruble | ₽ |
| KRW | South Korean Won | ₩ |
| SEK | Swedish Krona | kr |
| NOK | Norwegian Krone | kr |
| DKK | Danish Krone | kr |
| PLN | Polish Zloty | zł |
| CZK | Czech Koruna | Kč |
| HUF | Hungarian Forint | Ft |
| TRY | Turkish Lira | ₺ |

### Time Currency

| Code | Name | Description |
|------|------|-------------|
| MIN | Minutes | Base unit for time-based debts |

Time is always stored in **minutes**. UI displays human-readable formats:

| Minutes | Display |
|---------|---------|
| 30 | 30m |
| 90 | 1h 30m |
| 480 | 8h |
| 1440 | 1 day |
| 10080 | 1 week |
| 43200 | 1 month |

## Debt Lifecycle

```
[draft] → [pending] → [open] → [paid]
              ↓          │
         [rejected]      ├──→ [expired]
                         │
                         └──→ [retired]
```

### Status Values

| Status | Description | Transition |
|--------|-------------|------------|
| `draft` | Created locally, not sent | Local only |
| `pending` | Sent to counterparty | After `create` entry |
| `open` | Both parties signed | After `confirm` entry |
| `paid` | Balance is zero | After final payment + both parties confirm |
| `expired` | Due date passed | Both parties must agree |
| `retired` | Obligation abandoned | Both parties must agree |
| `rejected` | Counterparty declined | After reject entry |
| `uncollectable` | Debtor unavailable | Creditor declares (see below) |
| `unpayable` | Creditor unavailable | Debtor declares (see below) |

### Party Unavailability Status

When one party becomes unreachable or otherwise unavailable, the other party can close the debt by declaring the status. These statuses represent situations where normal debt resolution is impossible.

**Uncollectable** (declared by creditor):
- Debtor has become unreachable after reasonable attempts at contact
- Debtor has passed away
- Debtor is otherwise unable to fulfill the obligation
- Any situation where the creditor cannot reasonably expect to collect

**Unpayable** (declared by debtor):
- Creditor has become unreachable (debtor cannot make payments)
- Creditor has passed away
- Creditor is otherwise unable to receive payment
- Any situation where the debtor cannot reasonably make payment

**Requirements for declaration**:
- Must include detailed explanation in the entry content (reason: disappeared, deceased, etc.)
- Should attach supporting evidence if available (photos, death certificate reference, communication attempts)
- The declaration is a unilateral action (does not require confirmation from the missing party)
- Witnesses can add supporting `witness` entries if they have knowledge of the situation

**Example (Uncollectable)**:
```markdown
> 2026-08-15 10:00_00 -- X1ABCD
--> type: status_change
--> status: uncollectable
--> reason: disappeared
After 6 months of attempted contact via phone, email, and in-person visits,
I declare this debt as uncollectable. The debtor Y2EFGH has not responded
since 2026-02-15.
--> npub: npub1abc...
--> signature: 9a8b7c6d...
```

**Example (Unpayable)**:
```markdown
> 2026-08-15 10:00_00 -- Y2EFGH
--> type: status_change
--> status: unpayable
--> reason: deceased
I declare this debt as unpayable. The creditor X1ABCD has passed away
and I have been unable to identify their estate or successors to make payment.
--> npub: npub1def...
--> signature: 7c8d9e0f...
```

### Status Change Rules

| From | To | Required |
|------|-----|----------|
| `pending` | `open` | Counterparty `confirm` |
| `pending` | `rejected` | Counterparty `reject` |
| `open` | `paid` | Balance = 0 + both parties sign status_change |
| `open` | `expired` | Both parties sign status_change |
| `open` | `retired` | Both parties sign status_change |

## Signature Process

### Chain Signing

Each entry's signature covers **all content above it** in the file:

```
Entry 1 signature → signs: Header + Entry 1 content (before signature)
Entry 2 signature → signs: Header + Entry 1 + Entry 2 content (before signature)
Entry 3 signature → signs: Header + Entry 1 + Entry 2 + Entry 3 content (before signature)
```

This creates a tamper-evident chain where modifying any entry invalidates all signatures below it.

### NOSTR Event Structure

Signatures use NOSTR-compatible events (same as chat):

```json
{
  "pubkey": "hex_public_key",
  "created_at": 1704106800,
  "kind": 1,
  "tags": [
    ["t", "wallet"],
    ["debt_id", "debt_20260101_abc123"],
    ["callsign", "X1ABCD"]
  ],
  "content": "sha256_of_content_above",
  "id": "calculated_event_id",
  "sig": "schnorr_signature"
}
```

### Verification

To verify a debt ledger:

1. Parse all entries from the file
2. For each entry:
   - Extract content from file start up to (but not including) the signature line
   - Reconstruct NOSTR event with debt_id as room_id
   - Verify BIP-340 Schnorr signature
   - Mark entry as valid/invalid
3. If any entry is invalid, all entries below it are also invalid

### Media Verification

Photos include SHA1 hash in signed content:

```markdown
--> file: receipt.jpg
--> sha1: da39a3ee5e6b4b0d3255bfef95601890afd80709
```

To verify:
1. Calculate SHA1 of the referenced file
2. Compare with stored hash
3. Hash is included in signed content, preventing tampering

### Proof Code System

To prevent the use of old photos ("this photo wasn't taken for this transaction"), the app includes a **Proof Code** verification system:

1. **Code Generation**: When creating a debt or payment, the person being photographed opens a full-screen display showing:
   - A unique 3-character alphanumeric code
   - Current date and time
   - Transaction ID
   - Parties involved (creditor/debtor callsigns)
   - Amount

2. **Photo Capture**: The other party photographs the person holding their phone displaying this code

3. **Verification**: The photo's SHA1 hash is included in the signed debt entry:
   ```markdown
   --> file: identity_photo.jpg
   --> sha1: da39a3ee5e6b4b0d3255bfef95601890afd80709
   --> proof_code: X7K
   --> proof_timestamp: 1704106800000
   ```

4. **Anti-Tampering**: Since the proof code is:
   - Generated from transaction data + timestamp
   - Visible in the photo
   - Photo hash is included in signed content

   It's cryptographically impossible to substitute an old photo, as:
   - The code wouldn't match the transaction
   - Photoshopping would change the SHA1 hash
   - The signature covers the hash

**Code Format**: `PROOF|{code}|{date}|{time}|{transaction}|{creditor}|{debtor}|{amount}`

**Example**: `PROOF|X7K|2026-01-15|14:30:00|debt_20260115_abc123|X1ABCD|Y2EFGH|100.00 EUR`

## P2P Synchronization

### Identical Copies

Both parties (and witnesses) maintain identical copies of the `.md` file. Any new entry must be synchronized to all parties.

### Sync Flow

1. Party A adds new entry to their local file
2. Party A sends entire file to Party B via ConnectionManager
3. Party B verifies all signatures
4. Party B saves file (if valid) or rejects (if tampered)
5. Party B may add their own entry (e.g., `confirm_payment`)
6. Party B sends updated file back to Party A

### Transport

Uses ConnectionManager with automatic transport selection:

| Transport | Priority | Use Case |
|-----------|----------|----------|
| LAN | 10 | Same network |
| WebRTC | 15 | Direct P2P |
| Station | 30 | Internet relay |
| BLE+ | 35 | Bluetooth extended |
| BLE | 40 | Bluetooth basic |

### Anti-Spam

- Requests are queued when wallet app is not open
- Requests expire after 30 days
- Maximum 5 pending requests per sender
- Requests are only delivered when wallet is initialized

## API Endpoints

### Sync Requests

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/wallet/requests` | List pending sync requests |
| POST | `/api/wallet/sync` | Receive sync from other party |
| POST | `/api/wallet/requests/{id}/approve` | Approve and merge |
| POST | `/api/wallet/requests/{id}/reject` | Reject request |

### Local Management

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/wallet/debts` | List all debts |
| GET | `/api/wallet/debts/{id}` | Get debt details |
| POST | `/api/wallet/debts` | Create new debt |
| POST | `/api/wallet/debts/{id}/entries` | Add entry |
| GET | `/api/wallet/debts/{id}/verify` | Verify all signatures |
| GET | `/api/wallet/summary` | Summary (owed/owing) |

## Validation Rules

### File Level

- Must start with header line: `# debt_id: description`
- debt_id must match filename (without `.md`)
- File encoding: UTF-8
- Line endings: LF (`\n`)

### Entry Level

- Must have valid timestamp format: `YYYY-MM-DD HH:MM_ss`
- Must have valid callsign
- Must have `type` metadata
- Must have `npub` and `signature` as last two metadata fields

### Signature Level

- `signature` must be valid 128-character hex string
- Signature must verify against content above it
- `npub` must be valid bech32-encoded public key

### Amount Level

- Must be valid decimal number
- Currency must be from supported list
- Balance must not go negative

## Security Considerations

### Signature Chain Integrity

- Each signature covers all previous content
- Tampering with any entry invalidates all signatures below
- Old entries can always be verified independently
- New entries cannot modify history

### Key Management

- Private keys (`nsec`) must never be stored in debt files
- Public keys (`npub`) are safe to include
- Users should backup their keys securely

### Privacy

- Debt files contain financial information
- Consider encryption for sensitive debts
- Be cautious about witness selection
- Files can be moved to restricted folders

### Media Files

- Always verify SHA1 hash before trusting photos
- Photos are stored separately from ledger
- Hash is included in signature, preventing substitution

## Legal Compliance

This section outlines the legal requirements for digital debt contracts to be enforceable in court. The Wallet format is designed to meet or exceed these requirements.

### Default Terms and Conditions

Every debt contract automatically includes standard terms and conditions that establish the legal framework. These terms are embedded in the `create` entry content and are signed by both parties.

#### Terms Structure

```markdown
I am lending 100 EUR to Bob for car repair.

---
This agreement is subject to the Standard Terms and Conditions for Digital Debt Agreements, which both parties accept by signing. These terms ensure compliance with US (E-SIGN Act, UETA) and EU (eIDAS) electronic signature laws. The full terms are included below.

## Terms and Conditions

By signing this digital debt agreement, both parties agree to the following:

### 1. Electronic Signatures and Records
...
```

#### Standard Terms Summary

The default terms cover these key areas:

| Section | Purpose |
|---------|---------|
| **1. Electronic Signatures** | Establishes that signatures are legally binding under US E-SIGN/UETA and EU eIDAS |
| **2. Acknowledgment of Debt** | Debtor formally acknowledges the obligation |
| **3. Record Retention** | Both parties agree to keep records |
| **4. Identity Verification** | Cryptographic keys establish identity |
| **5. Amendments and Payments** | How changes are made and validated |
| **6. Witnesses** | Role of third-party attestation |
| **7. Dispute Resolution** | Cryptographic record is admissible as evidence |
| **8. Governing Law** | Default: creditor's jurisdiction (overridable) |
| **9. Severability** | Invalid provisions don't void the agreement |
| **10. Entire Agreement** | The ledger is the complete agreement |

#### Customization

When creating a debt, the following can be customized:

| Parameter | Description |
|-----------|-------------|
| `governingJurisdiction` | Override default jurisdiction (e.g., "California, USA" or "Germany") |
| `additionalTerms` | Add custom terms beyond the standard ones |
| `includeTerms` | Set to `false` to exclude standard terms (not recommended) |

#### Example with Custom Jurisdiction

```markdown
> 2026-01-01 10:00_00 -- X1ABCD
--> type: create
--> status: pending
--> creditor: X1ABCD
--> creditor_npub: npub1abc...
--> debtor: Y2EFGH
--> debtor_npub: npub1def...
--> amount: 100.00
--> currency: EUR
I am lending 100 EUR to Bob for car repair.

---
This agreement is subject to the Standard Terms and Conditions...

## Terms and Conditions

...

### 8. Governing Law

8.1. This agreement shall be governed by the laws of Portugal.

...
--> npub: npub1abc...
--> signature: 3a4f8c92...
```

### United States Legal Framework

#### E-SIGN Act (Federal)

The Electronic Signatures in Global and National Commerce Act (2000) establishes that electronic signatures are legally valid and enforceable. The Wallet format meets E-SIGN requirements:

| Requirement | How Wallet Meets It |
|-------------|---------------------|
| **Intent to sign** | Both parties must add signed entries to accept the debt |
| **Consent to electronic business** | Implicit consent by using the Wallet app |
| **Association with record** | Signature is embedded directly in the ledger file |
| **Record retention** | Both parties maintain identical copies of the file |

#### UETA (State Level)

The Uniform Electronic Transactions Act (adopted by 49 states + DC) provides additional state-level protections. Notable requirements:

- **Transferable records**: For promissory notes to be negotiable instruments, there must be "a single authoritative copy" that is "readily identifiable"
- **Wallet compliance**: The signature chain ensures authenticity; transfers create new ledgers with clear provenance

**Exceptions** (cannot use electronic signatures):
- Wills, codicils, testamentary trusts
- Divorce and adoption papers
- Court orders
- Some notarized contracts

#### Four Core Elements for Valid Digital Contracts

1. **Offer and Acceptance**: The `create` + `confirm` entries establish this
2. **Consideration**: The debt amount represents value exchanged
3. **Capacity**: Parties must be adults of sound mind (not enforced by format)
4. **Legality**: The subject matter must be legal

### European Union Legal Framework

#### eIDAS Regulation

The EU Electronic Identification and Trust Services Regulation provides legal recognition for electronic signatures across all EU member states.

**Types of Electronic Signatures under eIDAS**:

| Type | Legal Status | Wallet Implementation |
|------|--------------|----------------------|
| **Simple (SES)** | Valid, may require additional evidence | Wallet's cryptographic signatures exceed this |
| **Advanced (AdES)** | Guaranteed authenticity and integrity | Wallet uses BIP-340 Schnorr signatures (qualifies) |
| **Qualified (QES)** | Equivalent to handwritten signature | Requires certified Trust Service Provider |

**eIDAS 2.0 (2024-2025)**:
- Introduces EU Digital Identity Wallet (EUDI Wallet)
- By end of 2026, member states must offer digital identity wallets
- By 2027, certain industries must accept EUDI Wallet for identification

**Wallet compliance with eIDAS**:
- Signatures "cannot be denied legal validity solely because they are in electronic form"
- Cross-border validity: A debt signed in Estonia is valid in Spain, Portugal, etc.
- Advanced Electronic Signature requirements are met by BIP-340 signatures

**EU Exceptions** (cannot use electronic signatures):
- Real estate transfers (except rentals)
- Contracts requiring court/public authority involvement
- Suretyship by non-business persons
- Family law and succession matters

### Cryptographic Signatures as Legal Evidence

#### Court Admissibility

Courts increasingly accept cryptographic signatures as evidence:

- **US**: Under Federal Rules of Evidence, evidence must be relevant, authentic, and reliable
- **China**: Supreme People's Court (2018) ruled blockchain as valid method for "storing and authenticating digital evidence"
- **UK**: Pilot programs accepting blockchain-secured evidence

**Authentication Benefits of BIP-340 Signatures**:
- Cryptographic binding between signer and content
- Equivalent to having witnesses observe signing
- High barrier to contest ("I didn't sign that")
- Reduces enforcement costs

#### Signature Chain as Anti-Tampering

The Wallet's signature chain provides:
- **Immutability**: Each signature covers all content above it
- **Traceability**: Every entry has a verifiable author
- **Non-repudiation**: Cannot deny signing without breaking cryptographic proof

### Recommendations for Legal Enforceability

#### Essential Elements (Must Have)

| Element | How to Ensure |
|---------|---------------|
| **Clear identification of parties** | Include full names, callsigns, and npubs |
| **Specific amount and currency** | Always specify exact amount |
| **Clear terms** | Include repayment schedule, interest (if any), due date |
| **Mutual agreement** | Both parties must sign (`create` + `confirm`) |
| **Timestamp** | All entries include date/time |

#### Strongly Recommended

| Element | Benefit |
|---------|---------|
| **Witnesses** | Third-party witnesses strengthen legal standing |
| **Identity photos with proof code** | Prevents impersonation claims |
| **Description of consideration** | What the money/time is for |
| **Due date** | Clear repayment deadline |
| **Real names (not just callsigns)** | Use `creditor_name` and `debtor_name` fields |

#### Optional but Helpful

| Element | Benefit |
|---------|---------|
| **Notarization** | Not required but prevents identity disputes |
| **PDF export** | Courts may prefer conventional document format |
| **Hash of ledger file** | Additional proof of integrity |
| **Video call during signing** | Evidence of identity and understanding |

### Statute of Limitations

**Important**: Debt contracts have time limits for legal enforcement.

| Jurisdiction | Written Contracts | Promissory Notes |
|--------------|-------------------|------------------|
| US (varies by state) | 3-15 years | 3-15 years |
| UK | 6 years | 6 years |
| EU (varies) | 3-30 years | 3-30 years |

**Wallet recommendations**:
- Include clear due dates
- Track modification dates (`modifiedAt`)
- Keep records of all entries for the statute period

### Disclaimer

**Important**: This specification provides a technical format for recording debts with cryptographic signatures. It does NOT constitute legal advice. Users should:

1. Consult a licensed attorney for specific legal questions
2. Understand that enforceability varies by jurisdiction
3. Keep traditional paper records as backup where appropriate
4. Be aware that some types of debts may require specific formalities

The cryptographic signatures and proof code system are designed to meet or exceed typical contract requirements, but local laws may impose additional requirements.

---

*This specification is part of the Geogram project.*
*License: Apache-2.0*
