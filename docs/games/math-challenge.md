# Geogram Math Challenge

**Version**: 1.0
**Last Updated**: 2025-12-28
**Status**: Design

## Table of Contents

- [Overview](#overview)
- [Question Types](#question-types)
- [Difficulty Levels](#difficulty-levels)
- [P2P Challenge Mode](#p2p-challenge-mode)
- [Station Challenge Mode](#station-challenge-mode)
- [Game Flow](#game-flow)
- [Scoring System](#scoring-system)
- [Security & NOSTR Authentication](#security--nostr-authentication)
- [Data Format Specification](#data-format-specification)
- [Technical Integration](#technical-integration)

## Overview

Geogram Math Challenge is a competitive math game where players race to solve 10 mathematical questions across 10 difficulty levels. The game can be played in two modes: P2P via Bluetooth against another player, or against a station for station-specific leaderboard rankings.

### Key Features

- **10 Questions**: One question per difficulty level (1-10)
- **10 Minute Limit**: Maximum game duration
- **Full Math Variety**: Arithmetic, algebra, geometry, fractions, percentages
- **Two Game Modes**: P2P Bluetooth battles, Station challenges
- **Same Questions**: In P2P mode, both players solve identical questions
- **Station Leaderboards**: Per-station rankings for station challenges
- **NOSTR Signed**: Results are cryptographically signed to prevent cheating

### Win Condition

1. **Primary**: Most correct answers wins
2. **Tiebreaker**: Fastest total time wins

---

## Question Types

### Arithmetic

Basic mathematical operations with varying complexity.

| Type | Example (Easy) | Example (Hard) |
|------|----------------|----------------|
| Addition | 7 + 5 = ? | 847 + 396 = ? |
| Subtraction | 15 - 8 = ? | 1024 - 567 = ? |
| Multiplication | 6 × 4 = ? | 47 × 38 = ? |
| Division | 24 ÷ 6 = ? | 1296 ÷ 36 = ? |
| Order of Operations | 3 + 4 × 2 = ? | 15 + 8 × 6 - 12 ÷ 4 = ? |

### Algebra

Solving for unknowns and simplifying expressions.

| Type | Example (Easy) | Example (Hard) |
|------|----------------|----------------|
| Solve for X | x + 5 = 12 | 3x + 7 = 2x + 15 |
| Evaluate Expression | 2a when a=5 | 3x² - 2x + 1 when x=4 |
| Simplify | 3x + 2x = ? | 4(2x - 3) + 5x = ? |

### Geometry

Area, perimeter, and angle calculations.

| Type | Example |
|------|---------|
| Rectangle Area | Rectangle 8×5, area = ? |
| Triangle Area | Triangle base 10, height 6, area = ? |
| Circle Area | Circle radius 7, area = ? (use π ≈ 3.14) |
| Perimeter | Square side 9, perimeter = ? |
| Angles | Triangle angles 45° and 65°, third angle = ? |

### Fractions

Operations with fractional numbers.

| Type | Example (Easy) | Example (Hard) |
|------|----------------|----------------|
| Addition | 1/2 + 1/4 = ? | 3/8 + 5/12 = ? |
| Subtraction | 3/4 - 1/4 = ? | 7/10 - 2/15 = ? |
| Multiplication | 1/2 × 1/3 = ? | 5/6 × 9/10 = ? |
| Division | 1/2 ÷ 1/4 = ? | 7/8 ÷ 3/4 = ? |
| Simplify | 8/12 = ? | 45/60 = ? |

### Percentages

Percentage calculations and conversions.

| Type | Example |
|------|---------|
| Percentage of | 25% of 80 = ? |
| Find Percentage | 15 is what % of 60? |
| Increase/Decrease | 120 increased by 15% = ? |
| Decimal Conversion | 0.35 = ?% |
| Fraction Conversion | 3/5 = ?% |

---

## Difficulty Levels

Each game consists of exactly 10 questions, one from each difficulty level.

### Level Progression

| Level | Number Range | Question Types | Time Expectation |
|-------|--------------|----------------|------------------|
| 1 | 1-10 | Single operation (+, -) | < 10 sec |
| 2 | 1-20 | Single operation (+, -, ×) | < 15 sec |
| 3 | 1-50 | Single operation (all 4) | < 20 sec |
| 4 | 1-100 | Two operations | < 30 sec |
| 5 | 1-100 | Fractions, simple algebra | < 45 sec |
| 6 | 1-500 | Mixed operations, percentages | < 60 sec |
| 7 | 1-1000 | Complex expressions | < 90 sec |
| 8 | Any | Geometry problems | < 90 sec |
| 9 | Any | Multi-step problems | < 120 sec |
| 10 | Any | Advanced combinations | < 120 sec |

### Example Questions by Level

**Level 1**: 7 + 5 = ?
**Level 2**: 8 × 3 = ?
**Level 3**: 48 ÷ 6 = ?
**Level 4**: 15 + 8 × 3 = ?
**Level 5**: x + 7 = 15, x = ?
**Level 6**: 35% of 80 = ?
**Level 7**: 847 - 456 + 123 × 2 = ?
**Level 8**: Triangle with base 12 and height 8, area = ?
**Level 9**: If 3x + 5 = 20, what is 2x - 3?
**Level 10**: A rectangle's length is twice its width. If perimeter is 36, area = ?

---

## P2P Challenge Mode

### Discovery & Challenge

1. App scans for nearby players via Bluetooth
2. Player A initiates challenge to Player B
3. Player B receives notification and accepts/declines
4. If accepted, BLE connection established

### Question Synchronization

Both players receive **identical questions** generated from a shared seed:

1. Challenge initiator generates random seed
2. Seed transmitted to opponent
3. Both devices generate same 10 questions from seed
4. Questions presented in same order

### Simultaneous Play

- Both players start at same moment
- Each answers at their own pace
- No visibility into opponent's progress during game
- Results compared only at end

### P2P Game End

Game ends when BOTH players have either:
- Answered all 10 questions, OR
- 10 minutes elapsed

### Result Exchange

1. Both players compute their results locally
2. Results exchanged via Bluetooth
3. Both players sign the combined result record
4. Winner determined and displayed

---

## Station Challenge Mode

### Solo Time Attack

Station challenges are solo time attacks. The player picks a difficulty level and answers **10 questions all at that level**. Total time to complete all 10 determines their ranking.

### How It Works

1. Player visits station location (detected via BLE)
2. Player selects difficulty level (1-10)
3. 10 questions generated at that level
4. Timer starts, questions presented sequentially
5. Player answers each question
6. After 10 questions: total time recorded
7. Leaderboard updated if all answers correct

### Per-Level Leaderboards

Each station has 10 leaderboards, one per difficulty:

**Station X3ALPHA - Level 5 Leaderboard:**
| Rank | Callsign | Correct | Time | Date |
|------|----------|---------|------|------|
| 1 | X1FAST | 10/10 | 1:42 | 2025-12-28 |
| 2 | X1QUICK | 10/10 | 1:58 | 2025-12-27 |
| 3 | X1SMART | 10/10 | 2:15 | 2025-12-28 |

**Station X3ALPHA - Level 10 Leaderboard:**
| Rank | Callsign | Correct | Time | Date |
|------|----------|---------|------|------|
| 1 | X1GENIUS | 10/10 | 4:32 | 2025-12-28 |
| 2 | X1WIZARD | 10/10 | 5:15 | 2025-12-27 |
| 3 | X1MATH | 10/10 | 6:48 | 2025-12-28 |

### Leaderboard Rules

- Only 10/10 correct entries qualify for leaderboard
- Sorted by time (ascending) - fastest wins
- Top 50 entries per level per station
- Best time per player per level shown
- Player can retry to improve their time

### Station Configuration

```
math_challenge:
  enabled: true
  leaderboard_size_per_level: 50
  levels_enabled: [1,2,3,4,5,6,7,8,9,10]
  questions_per_challenge: 10
  max_time: 600
```

---

## Game Flow

### P2P Challenge Flow

**Phase 1: Initialization**
```
1. Challenge initiated via Bluetooth
2. Opponent accepts
3. Question seed generated and shared
4. Countdown: 3... 2... 1... GO!
```

**Phase 2: Questions**
```
For each level 1-10:
  1. Display question
  2. Start question timer
  3. Player submits answer
  4. Record: correct/incorrect + time
  5. Brief feedback (✓ or ✗)
  6. Next question

If total time > 10 minutes:
  End game immediately
  Unanswered questions = incorrect
```

**Phase 3: Results**
```
1. Calculate final score
2. Calculate total time
3. Exchange results via Bluetooth
4. Both players sign combined record
5. Display winner
```

**P2P UI:**
```
┌─────────────────────────────┐
│ Level 3/10          02:34   │
├─────────────────────────────┤
│                             │
│         48 ÷ 6 = ?          │
│                             │
│    ┌─────────────────┐      │
│    │                 │      │
│    └─────────────────┘      │
│                             │
│         [Submit]            │
│                             │
├─────────────────────────────┤
│ ✓✓✗ ○○○○○○○    Score: 20   │
└─────────────────────────────┘
```

### Station Time Attack Flow

**10 Questions at Selected Level:**
```
1. Player visits station
2. Selects difficulty level (1-10)
3. Timer starts
4. 10 questions presented sequentially
5. Player answers each
6. After question 10: total time recorded
7. If 10/10 correct: leaderboard updated
8. Station signs result
```

**Station UI:**
```
┌─────────────────────────────┐
│ Level 7 - Q3/10      01:12  │
├─────────────────────────────┤
│                             │
│   847 - 456 + 123 × 2 = ?   │
│                             │
│    ┌─────────────────┐      │
│    │                 │      │
│    └─────────────────┘      │
│                             │
│         [Submit]            │
│                             │
├─────────────────────────────┤
│ ✓✓○○○○○○○○   Your best: #3  │
└─────────────────────────────┘
```

---

## Scoring System

### Points

| Outcome | Points |
|---------|--------|
| Correct answer | 10 |
| Incorrect answer | 0 |
| Timeout (no answer) | 0 |
| **Maximum score** | **100** |

### Time Tracking

- **Per-question time**: Seconds to answer each question
- **Total time**: Sum of all answer times
- **Game time**: Wall clock from start to finish

### Ranking Calculation

Players are ranked by:
1. **Score** (primary, descending)
2. **Total time** (secondary, ascending)

Example ranking:
| Rank | Player | Score | Time |
|------|--------|-------|------|
| 1 | Alice | 100 | 3:42 |
| 2 | Bob | 100 | 4:15 |
| 3 | Carol | 90 | 3:30 |

Alice and Bob both scored 100, but Alice was faster.

---

## Security & NOSTR Authentication

### Core Principle

All results that affect station leaderboards must be cryptographically signed to prevent score fabrication.

### Question Seed Verification

Questions are generated deterministically:
```
hash(seed + level) → question_parameters → question
```

This allows:
- Both P2P players to have identical questions
- Stations to verify claimed seeds
- Auditors to reproduce questions

### P2P Result Signing

Both players must sign the result:

```
# MATH_CHALLENGE: <uuid>

MODE: p2p
TIMESTAMP: 2025-12-28 14:30:00
SEED: abc123def456

PLAYER_A: X1ALPHA
PLAYER_A_NPUB: npub1alpha...
PLAYER_A_SCORE: 80
PLAYER_A_TIME: 245
PLAYER_A_ANSWERS: 1,1,0,1,1,1,1,0,1,1

PLAYER_B: X1BRAVO
PLAYER_B_NPUB: npub1bravo...
PLAYER_B_SCORE: 70
PLAYER_B_TIME: 312
PLAYER_B_ANSWERS: 1,1,1,0,1,1,0,1,0,1

WINNER: player_a

--> signature_a: <hex_sig_from_player_a>
--> signature_b: <hex_sig_from_player_b>
```

**Fields:**
- `SEED`: Deterministic question generator seed
- `SCORE`: Total points (0-100)
- `TIME`: Total seconds to complete
- `ANSWERS`: Comma-separated (1=correct, 0=incorrect)

### Station Result Signing

Station signs time attack results:

```
# MATH_TIME_ATTACK: <uuid>

TIMESTAMP: 2025-12-28 14:30:00
SEED: xyz789ghi012

STATION: X3STATION01
STATION_NPUB: npub1station...

PLAYER: X1ALPHA
PLAYER_NPUB: npub1alpha...
LEVEL: 7
CORRECT: 10
TOTAL: 10
TIME_MS: 102000
LEADERBOARD_RANK: 3

--> npub: npub1station...
--> signature: <hex_sig_from_station>
```

**Fields:**
- `LEVEL`: Difficulty level (1-10)
- `CORRECT`: Number of correct answers
- `TOTAL`: Total questions (always 10)
- `TIME_MS`: Total milliseconds to complete
- `LEADERBOARD_RANK`: Position on level leaderboard (0 if not 10/10 or not in top 50)

### Cheating Prevention

| Cheat Attempt | Prevention |
|---------------|------------|
| Fabricate score | Requires station/opponent signature |
| Change answers | Answers included in signed data |
| Fake faster time | Time tracked by station/opponent |
| Reuse old result | Unique ID + timestamp verification |
| Modify questions | Seed is signed, questions reproducible |

---

## Data Format Specification

### Question Seed Format

```
seed:
  value: <32 char hex string>
  generated_by: <callsign>
  timestamp: 2025-12-28T14:30:00Z
```

### Generated Question Format

```
question:
  level: 5
  type: algebra
  text: "x + 7 = 15, x = ?"
  answer: 8
  answer_type: integer
  parameters:
    operation: addition
    unknown: left
    result: 15
    known: 7
```

### Station Leaderboard Format

Each station has 10 leaderboard files (one per level):

```
# LEADERBOARD: X3STATION01
# LEVEL: 7

UPDATED: 2025-12-28 15:00:00

> RANK:1 CALLSIGN:X1FAST TIME_MS:102000 DATE:2025-12-28
--> npub: npub1fast...

> RANK:2 CALLSIGN:X1QUICK TIME_MS:118000 DATE:2025-12-27
--> npub: npub1quick...

> RANK:3 CALLSIGN:X1SMART TIME_MS:135000 DATE:2025-12-28
--> npub: npub1smart...
```

Note: Only 10/10 correct entries appear on leaderboards.

**Storage Path:**
```
leaderboards/
  X3STATION01/
    level_01.txt
    level_02.txt
    ...
    level_10.txt
```

### Answer Types

| Type | Format | Example |
|------|--------|---------|
| integer | Whole number | 42 |
| decimal | Up to 2 places | 3.14 |
| fraction | a/b format | 3/4 |
| percentage | Number only | 25 (for 25%) |

---

## Technical Integration

### Existing Infrastructure

| Service | Usage |
|---------|-------|
| `ble_discovery_service.dart` | Player detection |
| `bluetooth_classic_service.dart` | Game data exchange |
| `station_service.dart` | Station detection and communication |
| `collection_service.dart` | Result storage |

### Question Generator Module

Deterministic question generation:

```dart
class MathQuestionGenerator {
  final String seed;

  MathQuestionGenerator(this.seed);

  Question generateForLevel(int level) {
    final hash = sha256('$seed:$level');
    final params = _paramsFromHash(hash, level);
    return _buildQuestion(params);
  }
}
```

### BLE Protocol

**P2P Challenge Flow:**
```
A -> B: MATH_CHALLENGE_REQUEST
B -> A: MATH_CHALLENGE_ACCEPT
A -> B: SEED:<seed_value>
A,B:    START_GAME
A,B:    [Play independently]
A -> B: RESULT:<score>:<time>:<answers>
B -> A: RESULT:<score>:<time>:<answers>
A -> B: SIGNATURE:<sig_a>
B -> A: SIGNATURE:<sig_b>
```

**Station Time Attack Flow:**
```
P -> S: MATH_TIME_ATTACK_REQUEST:<level>
S -> P: SEED:<seed_value>
S -> P: START
S:      [Timer starts]
For each question 1-10:
  S -> P: QUESTION:<q_num>:<text>
  P -> S: ANSWER:<q_num>:<answer>
  S -> P: CORRECT:<q_num>:<0|1>
S:      [Timer stops]
S -> P: FINAL:<correct>/<total>:<time_ms>:<rank>:<signature>
```

### Storage

```
collections/
  math_challenge/
    # Signed P2P game results
    p2p_results/
      <result-id>.txt

    # Signed station speed trial results
    speed_results/
      <result-id>.txt

    # Station leaderboards (station-side, per level)
    leaderboards/
      <station-callsign>/
        level_01.txt
        level_02.txt
        ...
        level_10.txt
```

### Offline Capabilities

| Feature | Offline Support |
|---------|-----------------|
| P2P challenges | Full (BLE only) |
| Station challenges | Full (station stores locally) |
| Question generation | Full (deterministic from seed) |
| Leaderboard view | Station-local only |

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-28 | Initial design specification |
