# Geogram Companions - Offgrid Pet Battle Game

**Version**: 1.1
**Last Updated**: 2025-12-28
**Status**: Design

## Table of Contents

- [Overview](#overview)
- [Pet System](#pet-system)
- [P2P Player Discovery](#p2p-player-discovery)
- [Battle System](#battle-system)
- [Solo Activities](#solo-activities)
- [Station Interactions](#station-interactions)
- [Items System](#items-system)
- [Points & Leaderboard](#points--leaderboard)
- [Security & NOSTR Authentication](#security--nostr-authentication)
- [Data Format Specification](#data-format-specification)
- [Technical Integration](#technical-integration)

## Overview

Geogram Companions is an offline-first pet battle game that uses Bluetooth to enable player-vs-player interactions without requiring internet connectivity. Inspired by Pokemon Go, players collect and evolve radio/tech-themed creatures, battle other players they encounter via Bluetooth, and earn rewards by visiting stations.

### Key Features

- **Offline-First**: Core gameplay works without internet via Bluetooth P2P
- **BLE Discovery**: Automatic detection and notification of nearby players
- **Station Rewards**: Earn items by visiting local mesh stations
- **Solo Activities**: Training, exploration, and challenges for low player density areas
- **Turn-Based Combat**: Strategic Pokemon-style battles over Bluetooth
- **Radio/Tech Theme**: Creatures inspired by mesh network and radio concepts

### Game Flow

1. New user receives a free starter pet
2. User explores with the app, discovering other players via Bluetooth
3. When another player is nearby, both receive notifications
4. Players can challenge each other to turn-based battles
5. Winning battles earns XP for pets and points for the leaderboard
6. Visiting stations provides reward boxes with items
7. Special bonus boxes available during events or scheduled windows

---

## Pet System

### Theme

All pets are Radio/Tech creatures inspired by mesh network concepts. Each has unique abilities themed around signal transmission, data processing, and electromagnetic phenomena.

### Species List

| Pet | Evolution | Type | Role | Description |
|-----|-----------|------|------|-------------|
| Sparkbit | Voltwave | Electric | Fast Attacker | Small spark creature with rapid attacks |
| Meshling | Gridmaster | Network | Support | Gains power when near other players |
| Beakcon | Radiraptor | Signal | Scout | Bird-like creature, excellent detection |
| Antennox | Towerbeast | Receiver | Tank | Bulky defender with antenna horns |
| Frequill | Spectrumspine | Wave | Area Damage | Porcupine with broadcasting quills |
| Pulsar | Quasar | Pulse | Rhythmic | Jellyfish-like with pulsing attacks |
| Bytepup | Gigahound | Data | Balanced | Digital dog, loyal starter companion |
| Staticat | Thunderfeline | Static | Burst | Cat that builds and releases charge |

### Base Stats

Each pet has four core stats:

| Stat | Description | Range |
|------|-------------|-------|
| Health (HP) | Hit points before knockout | 50-150 |
| Attack (ATK) | Physical damage output | 10-50 |
| Defense (DEF) | Damage reduction | 5-40 |
| Speed (SPD) | Turn order priority | 10-60 |

### Starter Pet Selection

New users choose one starter from three options:
- **Bytepup** - Balanced stats, recommended for beginners
- **Sparkbit** - High speed, glass cannon
- **Antennox** - High defense, slow but sturdy

### Experience & Leveling

- Pets gain XP from battles (win or lose)
- XP required per level: `100 * level`
- Max level: 50
- Stats increase by 2-5% per level based on species

### Evolution

Each pet has one evolution stage:
- Base evolution level: 25
- Some species require an evolution item in addition to level
- Evolution increases all base stats by 30%
- Evolved pets gain access to advanced abilities

**Evolution Items Required:**
| Pet | Item Required |
|-----|---------------|
| Meshling | Network Core |
| Pulsar | Energy Cell |
| Staticat | Capacitor |

---

## P2P Player Discovery

### Bluetooth Scanning

The game uses BLE (Bluetooth Low Energy) to continuously scan for nearby players. This works completely offline without requiring stations or internet.

### Discovery Protocol

1. App broadcasts BLE advertisement containing:
   - Geogram device ID
   - Player callsign
   - Top pet species and level
   - Battle availability flag

2. Nearby devices detect advertisement via BLE scanning

3. Upon detection, the app:
   - Parses player information from advertisement
   - Calculates approximate distance via RSSI
   - Triggers notification if within range (~50 meters)

### Notifications

When another player is detected:
- Push notification: "Player [callsign] is nearby! (Level [X] [PetName])"
- Notification includes option to challenge or dismiss
- Tapping opens the challenge dialog

### Notification Preferences

Users can configure notification behavior:

| Setting | Behavior |
|---------|----------|
| Always | Notify even when app is closed (background BLE) |
| App Open | Only notify when app is in foreground |
| Never | Disable player notifications |

### Challenge Flow

1. Player A taps "Challenge" on notification
2. Challenge request sent via BLE to Player B
3. Player B receives challenge notification
4. Player B accepts or declines
5. If accepted, both devices establish BLE connection for battle

---

## Battle System

### Overview

Battles are turn-based, similar to classic Pokemon mechanics. Each player selects their active pet and takes turns choosing actions.

### Turn Order

1. Compare Speed stats of active pets
2. Higher Speed acts first
3. Speed ties resolved randomly

### Actions

Each turn, a player chooses one action:

| Action | Effect |
|--------|--------|
| Attack | Deal damage based on ATK vs opponent DEF |
| Defend | Reduce incoming damage by 50% this turn |
| Item | Use an item from inventory (consumes turn) |
| Ability | Use pet's special ability (if available) |
| Flee | Attempt to escape (60% success, counts as loss) |

### Damage Calculation

```
Base Damage = Attacker.ATK * (1 - Defender.DEF / 100)
Random Factor = 0.85 to 1.15
Final Damage = floor(Base Damage * Random Factor)
```

Minimum damage is always 1.

### Special Abilities

Each pet type has unique abilities:

| Pet Type | Ability | Effect |
|----------|---------|--------|
| Electric | Surge | Next attack deals 1.5x damage |
| Network | Sync | If near 2+ players, heal 20% HP |
| Signal | Ping | Guaranteed hit, ignores DEF, low damage |
| Receiver | Absorb | Convert 25% damage taken to HP |
| Wave | Broadcast | Deal 50% ATK to all opponent pets |
| Pulse | Rhythm | Attack twice at 60% power each |
| Data | Download | Copy opponent's last ability |
| Static | Discharge | Deal stored charge as bonus damage |

### Win/Loss Conditions

- **Win**: Opponent's active pet reaches 0 HP
- **Loss**: Your active pet reaches 0 HP
- **Draw**: Both pets KO'd simultaneously (rare)

### Rewards

| Outcome | Pet XP | Player Points |
|---------|--------|---------------|
| Win | 50 + (opponent level * 5) | 10 |
| Loss | 20 + (opponent level * 2) | 2 |
| Draw | 35 + (opponent level * 3) | 5 |
| Flee | 0 | 0 |

---

## Solo Activities

For areas with low player density, solo activities ensure the game remains engaging.

### Daily Training

- Battle AI opponents to gain small amounts of XP
- 3 training battles per day (resets at midnight local time)
- XP reward: 15 per battle (no player points)
- AI difficulty scales with player's top pet level

### Exploration Rewards

- Visiting new geographic locations earns items
- Tracked by GPS grid cells (approximately 100m x 100m)
- First visit to a new cell: random item reward
- Revisiting after 24 hours: small XP bonus

### Pet Care

Pets have a "Condition" stat affecting performance:

| Condition | Effect | How to Improve |
|-----------|--------|----------------|
| Rested | +10% all stats | Wait 8 hours between battles |
| Fed | +5% HP regen | Use food items |
| Happy | +5% XP gain | Win battles, explore |
| Tired | -10% all stats | Too many battles without rest |

### Daily Challenges

Rotating challenges that reset each day:

| Challenge | Requirement | Reward |
|-----------|-------------|--------|
| Wanderer | Walk 2 km | 2 Potions |
| Explorer | Visit 5 new locations | Random Item |
| Trainer | Complete 3 training battles | 100 XP |
| Socializer | Detect 3 nearby players | Rare Item |

### Weekly Challenges

Larger challenges with better rewards:

| Challenge | Requirement | Reward |
|-----------|-------------|--------|
| Champion | Win 10 battles | Evolution Item |
| Adventurer | Visit 50 new locations | 500 XP |
| Collector | Catch 2 new species | Rare Pet Egg |
| Station Master | Visit 5 different stations | Bonus Box |

### Collection Goals

Long-term goals for completionists:
- Collect all 8 base species
- Evolve all 8 species
- Complete item encyclopedia
- Reach max level with one pet
- Reach max level with all pets

---

## Station Interactions

### Overview

Geogram mesh stations provide rewards to players who visit them in person. Stations operate independently without requiring internet.

### Reward Boxes

When visiting any active station:
1. Station detects player via BLE
2. Checks cooldown (one box per station per 4 hours)
3. If eligible, generates and delivers reward box
4. Player opens box to receive random items

**Standard Reward Box Contents:**
| Item | Probability |
|------|-------------|
| Potion | 40% |
| Super Potion | 20% |
| Stat Boost | 15% |
| Food Item | 15% |
| Rare Item | 8% |
| Evolution Item | 2% |

### Bonus Boxes

Enhanced reward boxes available under special conditions:

**Trigger 1: Geogram Events**
- When a Geogram event is linked to a station
- During event hours, station distributes bonus boxes
- Bonus boxes have 2x drop rates for rare items

**Trigger 2: Station-Scheduled Windows**
- Station operators can schedule bonus windows
- Configuration stored locally on station (no internet needed)
- Example: "Saturdays 14:00-16:00"

### Station Configuration

Station operators configure game rewards in station settings:

```
game:
  enabled: true
  reward_cooldown: 4h
  bonus_windows:
    - day: saturday
      start: 14:00
      end: 16:00
    - day: sunday
      start: 10:00
      end: 12:00
  event_bonus: true
```

### Cooldown Management

- Each player-station pair has independent cooldown
- Cooldown tracked by player callsign on station
- Station stores last visit timestamps locally
- Cooldowns survive station restarts

---

## Items System

### Healing Items

| Item | Effect | Rarity |
|------|--------|--------|
| Potion | Restore 30 HP | Common |
| Super Potion | Restore 60 HP | Uncommon |
| Hyper Potion | Restore 120 HP | Rare |
| Full Restore | Restore all HP | Very Rare |

### Stat Boost Items

Temporary boosts lasting one battle:

| Item | Effect | Rarity |
|------|--------|--------|
| Attack Boost | +20% ATK | Uncommon |
| Defense Boost | +20% DEF | Uncommon |
| Speed Boost | +20% SPD | Uncommon |
| Power Surge | +10% all stats | Rare |

### Food Items

Improve pet Condition:

| Item | Effect | Rarity |
|------|--------|--------|
| Snack | Restore Fed condition | Common |
| Treat | Restore Fed + Happy | Uncommon |
| Premium Food | Fully restore Condition | Rare |

### Evolution Items

Required for certain evolutions:

| Item | Required For | Rarity |
|------|--------------|--------|
| Network Core | Meshling → Gridmaster | Rare |
| Energy Cell | Pulsar → Quasar | Rare |
| Capacitor | Staticat → Thunderfeline | Rare |

### Item Rarity Distribution

| Rarity | Drop Rate | Color |
|--------|-----------|-------|
| Common | 45% | White |
| Uncommon | 30% | Green |
| Rare | 20% | Blue |
| Very Rare | 5% | Purple |

---

## Points & Leaderboard

### Point Earning

Points are earned through gameplay activities:

| Activity | Points |
|----------|--------|
| Battle Win | 10 |
| Battle Loss | 2 |
| Battle Draw | 5 |
| Station Visit | 3 |
| Bonus Box | 5 |
| Daily Challenge | 5 |
| Weekly Challenge | 20 |

### Leaderboard Categories

| Category | Scope | Reset |
|----------|-------|-------|
| Global | All players | Never |
| Regional | By country/region | Monthly |
| Weekly | All players | Weekly |
| Friends | Contacts only | Never |

### Ranking Tiers

Based on total accumulated points:

| Tier | Points Required | Badge |
|------|-----------------|-------|
| Novice | 0 | Bronze |
| Challenger | 500 | Silver |
| Expert | 2,000 | Gold |
| Master | 10,000 | Platinum |
| Legend | 50,000 | Diamond |

### Leaderboard Display

- Top 100 players shown per category
- Player's own rank always visible
- Shows: Rank, Callsign, Points, Top Pet, Tier Badge

---

## Security & NOSTR Authentication

All game state that affects player ranking or pet stats MUST be cryptographically signed using NOSTR Schnorr signatures. This prevents cheating by ensuring players cannot edit their own stats or fabricate battle results.

### Core Principle

**Player-editable data is untrusted.** Only signed records from authoritative sources are valid:
- Battle results: signed by BOTH participants
- Station rewards: signed by the station's nsec
- Pet evolution: derived from signed XP records
- Points: calculated from signed battle/reward logs only

### Signature Format

All signed records follow the Geogram NOSTR pattern:

```
--> npub: npub1...
--> signature: <hex_schnorr_signature>
```

The signature covers all content above it in the record.

### Battle Result Signing

Both players must sign the battle result for it to be valid:

```
battle:
  id: <uuid>
  timestamp: 2025-12-28T14:30:00Z
  player_a:
    callsign: X1ABC
    npub: npub1abc...
    pet: bytepup
    level: 15
  player_b:
    callsign: X1XYZ
    npub: npub1xyz...
    pet: sparkbit
    level: 12
  outcome: player_a_win
  turns: 8
  xp_awarded:
    player_a: 110
    player_b: 44
  points_awarded:
    player_a: 10
    player_b: 2
  --> signature_a: <hex_sig_from_player_a>
  --> signature_b: <hex_sig_from_player_b>
```

**Validation Rules:**
1. Both signatures must be present
2. Each signature must verify against respective npub
3. Battle data must be identical in both players' records
4. Timestamp must be recent (within 24 hours for sync)

### Station Reward Signing

Stations sign rewards they distribute:

```
reward:
  id: <uuid>
  station_callsign: X3STATION01
  station_npub: npub1station...
  player_callsign: X1ABC
  player_npub: npub1abc...
  timestamp: 2025-12-28T12:00:00Z
  type: bonus_box
  items:
    - potion: 2
    - attack_boost: 1
  next_available: 2025-12-28T16:00:00Z
  --> signature: <hex_sig_from_station>
```

**Validation Rules:**
1. Signature must verify against station_npub
2. Station callsign must be X3 prefix (valid station)
3. Player must have visited station (BLE proximity verified)
4. Cooldown must be respected per player-station pair

### Pet State Derivation

Pet stats are NOT stored directly. They are derived from signed records:

```
Pet Level = f(sum of XP from all signed battle records)
Pet Stats = base_stats[species] * level_multiplier * evolution_bonus
Inventory = sum of items from all signed reward records - used items
```

**What IS Stored (Signed):**
- Battle records (signed by both players)
- Reward records (signed by stations)
- Item usage records (signed by player, deducted from inventory)

**What is NOT Trusted:**
- Direct pet stat values
- Self-reported XP
- Unsigned inventory claims

### Item Usage Signing

When a player uses an item, they sign the usage:

```
item_usage:
  id: <uuid>
  player_callsign: X1ABC
  player_npub: npub1abc...
  timestamp: 2025-12-28T14:35:00Z
  item: potion
  context: battle_<battle_id>
  --> signature: <hex_sig_from_player>
```

Usage is only valid if:
1. Player has the item (from signed reward records minus prior usages)
2. Signature verifies
3. Context is valid (e.g., during an actual battle)

### Training Battle Signing

Solo training battles are signed by the player but award reduced XP:

```
training:
  id: <uuid>
  player_callsign: X1ABC
  player_npub: npub1abc...
  timestamp: 2025-12-28T10:00:00Z
  opponent_type: ai_level_15
  outcome: win
  xp_awarded: 15
  daily_count: 2
  --> signature: <hex_sig_from_player>
```

**Anti-Cheat Rules:**
- Max 3 training battles per day (verified by timestamps)
- XP capped at 15 per training (vs 50+ for real battles)
- Training battles award 0 leaderboard points

### Points Calculation

Points are NEVER stored directly. They are calculated:

```
Total Points =
  sum(battle.points_awarded where player won, signed by both) +
  sum(battle.points_awarded where player lost, signed by both) +
  sum(reward.points where type=station_visit, signed by station) +
  sum(challenge.points, signed by player with valid conditions)
```

### Leaderboard Verification

When syncing leaderboards (online):
1. Player submits all signed battle/reward records
2. Server independently calculates points from records
3. Only verified records count toward ranking
4. Conflicting or unsigned records are rejected

### Offline Accumulation

While offline:
- Battles and rewards accumulate as signed records
- Local display shows calculated stats (for UX)
- Sync validates and commits to global leaderboard

### Cheating Prevention Summary

| Cheat Attempt | Prevention |
|---------------|------------|
| Edit own pet stats | Stats derived from signed XP records |
| Fabricate battle wins | Requires opponent's signature |
| Fake station rewards | Requires station's signature |
| Duplicate items | Inventory derived from signed rewards minus signed usages |
| Inflate points | Points calculated from signed records only |
| Spam training | Max 3/day, low XP, 0 points |
| Replay old battles | Timestamps + unique IDs |

### Key Management

- Player keys: Managed by Geogram profile (npub/nsec)
- Station keys: Configured in station setup
- All signatures use NOSTR Schnorr (secp256k1)

---

## Data Format Specification

### Authoritative Records (Signed)

These records are the source of truth. All stats are derived from them.

#### Battle Record (Signed by Both Players)

```
# BATTLE: <uuid>

TIMESTAMP: 2025-12-28 14:30:00
PLAYER_A: X1ABC
PLAYER_A_NPUB: npub1abc...
PLAYER_A_PET: bytepup
PLAYER_A_LEVEL: 15
PLAYER_B: X1XYZ
PLAYER_B_NPUB: npub1xyz...
PLAYER_B_PET: sparkbit
PLAYER_B_LEVEL: 12
OUTCOME: player_a_win
TURNS: 8
XP_A: 110
XP_B: 44
POINTS_A: 10
POINTS_B: 2

--> signature_a: <hex_sig_from_player_a>
--> signature_b: <hex_sig_from_player_b>
```

#### Station Reward Record (Signed by Station)

```
# REWARD: <uuid>

TIMESTAMP: 2025-12-28 12:00:00
STATION: X3STATION01
STATION_NPUB: npub1station...
PLAYER: X1ABC
PLAYER_NPUB: npub1abc...
TYPE: bonus_box
ITEMS: potion:2, attack_boost:1
POINTS: 3
NEXT_AVAILABLE: 2025-12-28 16:00:00

--> npub: npub1station...
--> signature: <hex_sig_from_station>
```

#### Item Usage Record (Signed by Player)

```
# ITEM_USAGE: <uuid>

TIMESTAMP: 2025-12-28 14:35:00
PLAYER: X1ABC
ITEM: potion
QUANTITY: 1
CONTEXT: battle_<battle_uuid>

--> npub: npub1abc...
--> signature: <hex_sig_from_player>
```

#### Training Record (Signed by Player)

```
# TRAINING: <uuid>

TIMESTAMP: 2025-12-28 10:00:00
PLAYER: X1ABC
OPPONENT_TYPE: ai_level_15
OUTCOME: win
XP: 15
DAILY_COUNT: 2

--> npub: npub1abc...
--> signature: <hex_sig_from_player>
```

#### Pet Acquisition Record (Signed by Source)

```
# PET_ACQUIRED: <uuid>

TIMESTAMP: 2025-12-28 08:00:00
PLAYER: X1ABC
PLAYER_NPUB: npub1abc...
SPECIES: bytepup
SOURCE: starter_selection
NICKNAME: Sparky

--> npub: npub1abc...
--> signature: <hex_sig>
```

For pets from reward boxes, signed by station:
```
SOURCE: reward_<reward_uuid>
--> npub: npub1station...
--> signature: <hex_sig_from_station>
```

### Derived Data (Cached, Not Authoritative)

Local cache for UI performance. Rebuilt from signed records on sync.

#### Pet Cache

```
pet:
  id: <uuid>
  species: bytepup
  nickname: Sparky
  level: 15              # Derived from sum of XP in signed records
  experience: 1200       # Derived from signed battle/training records
  evolved: false         # Derived from level + evolution item usage
  stats:                 # Derived from species base + level
    health: 85
    attack: 28
    defense: 22
    speed: 35
  condition:             # Local state, not competitive
    fed: true
    rested: true
    happy: true
  acquired: 2025-12-28T08:00:00Z
```

#### Inventory Cache

```
inventory:
  # Derived from: signed rewards - signed usages
  potion: 5
  super_potion: 2
  attack_boost: 1
```

#### Points Cache

```
points:
  # Derived from: sum of all signed battle + reward points
  total: 1250
  tier: challenger
  battles_won: 45        # Count of signed battles where outcome=win
  battles_lost: 12       # Count of signed battles where outcome=loss
  stations_visited: 23   # Count of unique station rewards
```

---

## Technical Integration

### Existing Infrastructure

The game integrates with existing Geogram services:

| Service | Usage |
|---------|-------|
| `ble_discovery_service.dart` | Player detection and notifications |
| `bluetooth_classic_service.dart` | Battle data exchange |
| `station_service.dart` | Station detection and rewards |
| `collection_service.dart` | Game state persistence |
| `profile_service.dart` | Player identity |

### BLE Advertisement Format

Game data included in BLE advertisement:

```
Bytes 0-3: Geogram magic bytes
Bytes 4-11: Device ID
Bytes 12-15: Callsign (compressed)
Byte 16: Game enabled flag
Byte 17: Top pet species ID
Byte 18: Top pet level
Byte 19: Battle availability (0=busy, 1=available)
```

### Battle Protocol

P2P battle communication over Bluetooth:

1. **Handshake**: Exchange player info and pet data
2. **Turn Loop**:
   - Active player sends action
   - Opponent receives and validates
   - Both calculate outcome
   - State synced between devices
3. **Resolution**: Final state confirmed, rewards calculated

### Offline Capabilities

| Feature | Offline Support |
|---------|-----------------|
| Pet management | Full |
| Training battles | Full |
| Player discovery | Full (BLE) |
| P2P battles | Full (BLE) |
| Station rewards | Full |
| Leaderboard | Syncs when online |
| Exploration | Full (GPS only) |

### Storage

Game data stored in Geogram collection format:

```
collections/
  game/
    # Authoritative signed records (source of truth)
    records/
      battles/
        <battle-id>.txt      # Signed by both players
      rewards/
        <reward-id>.txt      # Signed by station
      training/
        <training-id>.txt    # Signed by player
      item_usage/
        <usage-id>.txt       # Signed by player
      pets_acquired/
        <acquisition-id>.txt # Signed by source

    # Derived cache (rebuilt from records)
    cache/
      pets.txt               # Pet stats cache
      inventory.txt          # Item counts cache
      points.txt             # Points/ranking cache
      state.txt              # General game state
```

**Sync Process:**
1. Exchange signed records with peers/server
2. Validate all signatures
3. Rebuild cache from verified records
4. Update local UI

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | 2025-12-28 | Added NOSTR authentication and signed records |
| 1.0 | 2025-12-28 | Initial design specification |
