# Geogram Card Games

**Version**: 1.1
**Last Updated**: 2025-12-28
**Status**: Design

## Table of Contents

- [Overview](#overview)
- [Poker (Texas Hold'em)](#poker-texas-holdem)
- [Blackjack Duel](#blackjack-duel)
- [Rommé (German Rummy)](#rommé-german-rummy)
- [Shared Infrastructure](#shared-infrastructure)
- [Security & NOSTR Authentication](#security--nostr-authentication)
- [Data Format Specification](#data-format-specification)
- [Technical Integration](#technical-integration)

## Overview

Classic card games adapted for P2P Bluetooth play. All games use cryptographic deck shuffling to ensure fairness and NOSTR signing to prevent cheating.

### Included Games

| Game | Players | Style | Duration |
|------|---------|-------|----------|
| Poker (Texas Hold'em) | 2-4 | Bluffing, betting | 15-30 min |
| Blackjack Duel | 2-4 | Luck/skill, quick rounds | 10-15 min |
| Rommé | 2-4 | Set collection, strategy | 20-45 min |

### Key Features

- **P2P Bluetooth**: No internet required
- **Fair Shuffling**: Cryptographic seed ensures both see same deck
- **Face-to-Face Bluffing**: Being physically present adds social element
- **Station Leaderboards**: Optional ranked play per station
- **NOSTR Signed**: Results are cryptographically verified

---

## Poker (Texas Hold'em)

### Game Summary

Texas Hold'em poker for 2-4 players. Each player gets 2 hole cards, 5 community cards are revealed progressively. Best 5-card hand wins the pot.

### Setup

| Element | Value |
|---------|-------|
| Players | 2-4 |
| Deck | 52 cards (standard) |
| Hole cards | 2 per player |
| Community cards | 5 (flop 3, turn 1, river 1) |
| Starting chips | 1000 each |
| Blinds | Small 10, Big 20 |
| Blind increase | Every 10 hands (optional) |

### Hand Rankings (High to Low)

1. **Royal Flush**: A K Q J 10 same suit
2. **Straight Flush**: 5 sequential same suit
3. **Four of a Kind**: 4 same rank
4. **Full House**: 3 of a kind + pair
5. **Flush**: 5 same suit
6. **Straight**: 5 sequential
7. **Three of a Kind**: 3 same rank
8. **Two Pair**: 2 different pairs
9. **One Pair**: 2 same rank
10. **High Card**: Highest card wins

### Game Flow

```
1. Dealer button assigned (alternates each hand)
2. Blinds posted (small blind, big blind)
3. Hole cards dealt (2 each)
4. Pre-flop betting round
5. Flop dealt (3 community cards)
6. Flop betting round
7. Turn dealt (1 community card)
8. Turn betting round
9. River dealt (1 community card)
10. River betting round
11. Showdown (if not folded)
12. Winner takes pot
```

### Betting Actions

| Action | Description |
|--------|-------------|
| **Fold** | Surrender hand, lose current bets |
| **Check** | Pass action (if no bet to match) |
| **Call** | Match current bet |
| **Raise** | Increase the bet |
| **All-In** | Bet all remaining chips |

### Betting Rules

- Minimum raise = previous raise amount
- No limit on raise amount (No-Limit Hold'em)
- All-in creates side pot if opponent has more chips

### Win Conditions

**Hand Win:**
- Best 5-card hand at showdown
- All other players fold

**Match Win:**
- Last player with chips remaining
- Or most chips when time/hand limit reached

### P2P Protocol (Multi-Player)

```
All:    Generate shared seed (combine all player seeds) → shuffle deck
Dealer: Deal hole cards (encrypted to each player)
Each betting round:
  For each active player (clockwise):
    Active: ACTION:<fold|check|call|raise>:<amount>
    Others: ACK
Showdown:
  Remaining: REVEAL:<hole_cards>
  All:      VERIFY (decrypt and confirm)
Winner: Best hand takes pot (split if tie)
```

### Turn Order

- Dealer button rotates clockwise each hand
- Small blind: left of dealer
- Big blind: left of small blind
- First to act pre-flop: left of big blind
- First to act post-flop: left of dealer

### UI Layout (4 Players)

```
┌─────────────────────────────────────┐
│ P2: 850 [??][??]   P3: 720 [??][??]│
│         (folded)         (active)   │
├─────────────────────────────────────┤
│                                     │
│     [7♠] [7♦] [K♣] [2♥] [9♠]       │
│           Community                 │
│                                     │
│          Pot: 320                   │
│                                     │
│ P4: 430 [??][??]                   │
│       (all-in)                      │
├─────────────────────────────────────┤
│ [A♥] [A♠]                          │
│ Your hand: Pair of Aces             │
│ You: 950 chips                      │
├─────────────────────────────────────┤
│ [Fold] [Check] [Raise +20] [All-In] │
└─────────────────────────────────────┘
```

---

## Blackjack Duel

### Game Summary

2-4 players compete against a shared dealer. Each plays their hand independently, then compare results. Beat the dealer with a higher score (without busting).

### Setup

| Element | Value |
|---------|-------|
| Players | 2-4 |
| Decks | 6 decks (312 cards) shuffled |
| Starting chips | 500 each |
| Bet range | 10-100 per round |
| Rounds | Best of 10 or until one player remains |

### Card Values

| Card | Value |
|------|-------|
| 2-10 | Face value |
| J, Q, K | 10 |
| Ace | 1 or 11 (player's choice) |

### Game Flow

```
1. All players place bets (hidden until revealed)
2. Bets revealed simultaneously
3. Dealer deals:
   - 2 cards to each player (visible only to that player)
   - 2 cards to Dealer (1 up, 1 down)
4. Each player plays in turn (Hit/Stand/Double/Split)
5. Dealer reveals and plays (must hit on 16, stand on 17)
6. Results compared:
   - Beat dealer = win bet
   - Lose to dealer = lose bet
   - Push = bet returned
7. Compare chip totals after round
```

### Player Actions

| Action | Description |
|--------|-------------|
| **Hit** | Take another card |
| **Stand** | Keep current hand |
| **Double Down** | Double bet, take exactly 1 card, then stand |
| **Split** | If pair, split into 2 hands (bet on each) |

### Scoring

| Outcome | Result |
|---------|--------|
| Blackjack (21 with 2 cards) | Win 1.5x bet |
| Beat dealer | Win 1x bet |
| Tie (push) | Bet returned |
| Bust (over 21) | Lose bet |
| Dealer beats you | Lose bet |

### Round Comparison

After each round, compare performance:

| Scenario | Standing |
|----------|----------|
| Beat dealer, others lost | Gained ground |
| All beat dealer | Compare chip gains |
| Lost to dealer, others won | Lost ground |
| All lost to dealer | No change |

### Win Condition

- **Chip Victory**: All other players reach 0 chips
- **Round Victory**: After 10 rounds, most chips wins
- **Elimination**: Player at 0 chips is out
- **Surrender**: Player forfeits match

### UI Layout (4 Players)

```
┌─────────────────────────────────────┐
│            DEALER                   │
│           [K♠] [??]                 │
│           Shows: 10                 │
├─────────────────────────────────────┤
│ P2: 470      P3: 380      P4: 290  │
│ [??][??]     [??][??]     [??][??] │
│ Bet: 20      Bet: 50      Bet: 30  │
│ (waiting)    (bust!)      (stand)  │
├─────────────────────────────────────┤
│ YOU: 520 chips                      │
│ [J♥] [8♣]  Total: 18               │
│ Bet: 30                             │
├─────────────────────────────────────┤
│ [Hit] [Stand] [Double]              │
└─────────────────────────────────────┘
```

---

## Rommé (German Rummy)

### Game Summary

Classic German Rummy for 2-4 players. Draw and discard to form melds (sets and runs). First to play all cards or lowest deadwood points wins.

### Setup

| Element | Value |
|---------|-------|
| Players | 2-4 |
| Decks | 2 French decks + 6 jokers (110 cards) |
| Hand size | 13 cards each |
| First meld | Must total 30+ points |
| Jokers | Wild, can substitute any card |

### Card Points

| Card | Meld Value | Deadwood Value |
|------|------------|----------------|
| A | 1 or 11 (in runs) | 11 |
| 2-10 | Face value | Face value |
| J, Q, K | 10 | 10 |
| Joker | Value of card it replaces | 20 |

### Meld Types

**Set (Satz):**
- 3 or 4 cards of same rank, different suits
- Example: 7♠ 7♥ 7♦

**Run (Sequenz):**
- 3+ sequential cards of same suit
- Example: 4♣ 5♣ 6♣ 7♣
- Ace can be low (A-2-3) or high (Q-K-A), not both (K-A-2)

### Game Flow

```
1. Deal 13 cards to each player
2. Place remaining deck face-down (draw pile)
3. Flip top card to start discard pile
4. Players take turns clockwise:
   a. Draw (from pile or discard)
   b. Optionally: meld, lay off, swap jokers
   c. Discard one card
5. Game ends when any player empties hand
6. All others score deadwood points
```

### Turn Actions

| Action | Description |
|--------|-------------|
| **Draw** | Take from draw pile OR top of discard pile |
| **Meld** | Play valid set or run from hand (first meld needs 40+ points) |
| **Lay Off** | Add cards to existing melds (yours or opponent's) |
| **Swap Joker** | Replace a melded joker with the card it represents |
| **Discard** | Place one card on discard pile (required to end turn) |

### First Meld Requirement

Your first meld(s) in a round must total at least 30 points:
- 7♠ 7♥ 7♦ = 21 points (not enough alone)
- 7♠ 7♥ 7♦ + 3♣ 4♣ 5♣ = 21 + 12 = 33 points (valid)
- Q♣ Q♥ Q♠ = 30 points (valid)

After first meld, you can play any valid meld.

### Joker Rules

- Joker substitutes any card in a meld
- When laying off, you can swap a joker for the real card
- Swapped joker must be used immediately in another meld
- Cannot hold joker if you could play it

### Scoring

**Round End:**
- Winner (empty hand): 0 points
- Others: Sum of deadwood (cards in hand)

**Match:**
- First to reach target score loses (e.g., 200 points)
- Or play fixed rounds, lowest total wins
- Eliminated players can watch remaining

**Bonus Points:**
| Achievement | Bonus |
|-------------|-------|
| Rommé (out with no prior melds) | Double points to all others |
| Hand Rommé (out on first turn) | Triple points to all others |

### P2P Synchronization (Multi-Player)

```
All:    Agree on combined seed → shuffle deck
All:    Draw initial 13 cards
Each turn (clockwise):
  Active: DRAW:<pile|discard>
  Active: MELD:<cards> (optional, can repeat)
  Active: LAYOFF:<meld_id>:<cards> (optional)
  Active: DISCARD:<card>
  All:    Update game state, next player
End:
  Winner: ROMMÉ or OUT
  All:    Calculate and sign scores
```

### UI Layout (4 Players)

```
┌─────────────────────────────────────┐
│ P2: 8 cards   P3: 5 cards   P4: 10 │
├─────────────────────────────────────┤
│ Table melds:                        │
│ P2: [5♠6♠7♠8♠] [Q♥Q♦Q♣]            │
│ P3: [9♣10♣J♣] [4♥4♦4♠]             │
│ You: [K♠K♥K♦]                       │
│ P4: (none yet)                      │
├─────────────────────────────────────┤
│                                     │
│    Draw: [##]    Discard: [J♦]     │
│         P3's turn                   │
├─────────────────────────────────────┤
│ Your hand: (6 cards, 31 deadwood)   │
│ [2♠] [5♦] [8♥] [8♣] [A♣] [★]       │
├─────────────────────────────────────┤
│ [Draw Pile] [Take Discard] [Meld]   │
└─────────────────────────────────────┘
```

---

## Shared Infrastructure

### Cryptographic Deck Shuffling

All players must see the same shuffled deck without any player controlling it:

```
1. Each player generates secret: seed_1, seed_2, seed_3, seed_4
2. Exchange hashes: hash(seed_1), hash(seed_2), ...
3. All reveal secrets (verify against hashes)
4. Combined seed = hash(seed_1 + seed_2 + seed_3 + seed_4)
5. Shuffle deck deterministically from combined seed
```

This ensures:
- No player can control the shuffle
- All produce identical deck order
- Cheating is detectable
- Works for 2-4 players

### Card Encryption (Hidden Cards)

For games where cards are hidden (opponent's hand, hole cards):

```
1. Cards assigned at shuffle
2. Encrypted with recipient's public key
3. Only revealed when rules require
4. Revealed cards signed to prevent modification
```

### Game Session

```
session:
  id: <uuid>
  game: poker|blackjack|romme
  player_count: 4
  seeds:
    - player: X1ALPHA, seed: <hex>
    - player: X1BRAVO, seed: <hex>
    - player: X1CHARLIE, seed: <hex>
    - player: X1DELTA, seed: <hex>
  combined_seed: <hash>
  started: 2025-12-28T14:00:00Z
```

---

## Security & NOSTR Authentication

### Result Signing

All game results are signed by all players:

```
# CARD_GAME: <uuid>

GAME: poker
TIMESTAMP: 2025-12-28 14:30:00
COMBINED_SEED: abc123...
PLAYER_COUNT: 4

PLAYER_1: X1ALPHA
PLAYER_1_NPUB: npub1alpha...
PLAYER_1_RESULT: 1st
PLAYER_1_CHIPS: 2100

PLAYER_2: X1BRAVO
PLAYER_2_NPUB: npub1bravo...
PLAYER_2_RESULT: 2nd
PLAYER_2_CHIPS: 900

PLAYER_3: X1CHARLIE
PLAYER_3_NPUB: npub1charlie...
PLAYER_3_RESULT: 3rd
PLAYER_3_CHIPS: 0

PLAYER_4: X1DELTA
PLAYER_4_NPUB: npub1delta...
PLAYER_4_RESULT: 4th
PLAYER_4_CHIPS: 0

--> signature_1: <hex_sig>
--> signature_2: <hex_sig>
--> signature_3: <hex_sig>
--> signature_4: <hex_sig>
```

### Anti-Cheat Measures

| Cheat Attempt | Prevention |
|---------------|------------|
| Control deck shuffle | Combined seed from both players |
| See hidden cards | Encrypted until reveal |
| Modify revealed cards | Cards are signed |
| Fake results | Both players sign final result |
| Replay old games | Unique session ID + timestamp |

### Station Leaderboards (Optional)

Stations can track card game rankings:

```
# LEADERBOARD: X3STATION01
# GAME: poker

UPDATED: 2025-12-28 15:00:00

> RANK:1 CALLSIGN:X1SHARK WINS:45 LOSSES:12 WINRATE:78.9
> RANK:2 CALLSIGN:X1ACE WINS:38 LOSSES:15 WINRATE:71.7
> RANK:3 CALLSIGN:X1BLUFF WINS:52 LOSSES:22 WINRATE:70.3
```

---

## Data Format Specification

### Game Result Format

**Poker (4 players):**
```
# POKER_RESULT: <uuid>

TIMESTAMP: 2025-12-28 14:30:00
SEED: <combined_seed>
PLAYER_COUNT: 4

RESULTS:
  - PLAYER:X1ALPHA NPUB:npub1alpha... PLACE:1 CHIPS:2100
  - PLAYER:X1BRAVO NPUB:npub1bravo... PLACE:2 CHIPS:900
  - PLAYER:X1CHARLIE NPUB:npub1charlie... PLACE:3 CHIPS:0
  - PLAYER:X1DELTA NPUB:npub1delta... PLACE:4 CHIPS:0

HANDS_PLAYED: 35

--> signature_1: <hex_sig>
--> signature_2: <hex_sig>
--> signature_3: <hex_sig>
--> signature_4: <hex_sig>
```

**Blackjack (4 players):**
```
# BLACKJACK_RESULT: <uuid>

TIMESTAMP: 2025-12-28 14:30:00
SEED: <combined_seed>
PLAYER_COUNT: 4

ROUNDS: 10
RESULTS:
  - PLAYER:X1ALPHA NPUB:npub1alpha... PLACE:1 CHIPS:720
  - PLAYER:X1BRAVO NPUB:npub1bravo... PLACE:2 CHIPS:580
  - PLAYER:X1CHARLIE NPUB:npub1charlie... PLACE:3 CHIPS:200
  - PLAYER:X1DELTA NPUB:npub1delta... PLACE:4 CHIPS:0

--> signature_1: <hex_sig>
--> signature_2: <hex_sig>
--> signature_3: <hex_sig>
--> signature_4: <hex_sig>
```

**Rommé (4 players):**
```
# ROMME_RESULT: <uuid>

TIMESTAMP: 2025-12-28 14:30:00
SEED: <combined_seed>
PLAYER_COUNT: 4

ROUNDS: 5
RESULTS:
  - PLAYER:X1ALPHA NPUB:npub1alpha... PLACE:1 SCORE:45
  - PLAYER:X1BRAVO NPUB:npub1bravo... PLACE:2 SCORE:112
  - PLAYER:X1CHARLIE NPUB:npub1charlie... PLACE:3 SCORE:187
  - PLAYER:X1DELTA NPUB:npub1delta... PLACE:4 SCORE:203

--> signature_1: <hex_sig>
--> signature_2: <hex_sig>
--> signature_3: <hex_sig>
--> signature_4: <hex_sig>
```

### Storage

```
collections/
  card_games/
    results/
      poker/
        <result-id>.txt
      blackjack/
        <result-id>.txt
      romme/
        <result-id>.txt
    leaderboards/
      <station-callsign>/
        poker.txt
        blackjack.txt
        romme.txt
```

---

## Technical Integration

### BLE Protocol (Multi-Player)

**Game Initiation (4 players):**
```
Host:   CARD_GAME_INVITE:<game_type>
Others: CARD_GAME_JOIN
Host:   GAME_READY (when 2-4 players joined)
All:    SEED_HASH:<hash_of_my_seed>
All:    SEED_REVEAL:<my_seed> (after all hashes received)
All:    Calculate combined_seed, shuffle deck
All:    START_GAME
```

**In-Game Communication:**
```
Poker:
  DEAL:<player_id>:<encrypted_cards>
  TURN:<player_id>
  ACTION:<player_id>:<fold|check|call|raise>:<amount>
  REVEAL:<player_id>:<hole_cards>

Blackjack:
  BET:<player_id>:<amount>
  TURN:<player_id>
  ACTION:<player_id>:<hit|stand|double|split>
  DEALER:<cards>
  RESULT:<player_id>:<win|lose|push>

Rommé:
  TURN:<player_id>
  DRAW:<player_id>:<pile|discard>
  MELD:<player_id>:<card_list>
  LAYOFF:<player_id>:<meld_id>:<card_list>
  DISCARD:<player_id>:<card>
  OUT:<player_id>
```

### Existing Services

| Service | Usage |
|---------|-------|
| `ble_discovery_service.dart` | Find nearby players |
| `bluetooth_classic_service.dart` | Game data exchange |
| `station_service.dart` | Leaderboard storage |
| `collection_service.dart` | Result storage |

### Offline Support

| Feature | Offline Support |
|---------|-----------------|
| P2P games | Full (BLE only) |
| Result storage | Local until sync |
| Leaderboards | Station-local |

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2025-12-28 | Updated all games to support 2-4 players |
| 1.0 | 2025-12-28 | Initial design: Poker, Blackjack, Rommé |
