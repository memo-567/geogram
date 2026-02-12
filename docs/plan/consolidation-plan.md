# PureStationServer Consolidation Plan

## Overview

This document outlines the remaining work to consolidate `lib/cli/pure_station.dart` (12,136 lines) with the `lib/server/` unified architecture (1,672 lines total).

## Current State

### Already Shared (Phases 1-3 Complete)

| Component | Lines Saved | Location |
|-----------|-------------|----------|
| GeometryUtils | 24 | lib/api/common/geometry_utils.dart |
| FileTreeBuilder | 43 | lib/api/common/file_tree_builder.dart |
| StationInfo | 26 | lib/api/common/station_info.dart |
| ServerChatRoom | 76 | lib/server/models/server_chat_room.dart |
| ServerChatMessage | 121 | lib/server/models/server_chat_message.dart |
| IpRateLimit | 26 | lib/server/mixins/rate_limit_mixin.dart |
| AlertHandler | (pre-existing) | lib/api/handlers/alert_handler.dart |
| PlaceHandler | (pre-existing) | lib/api/handlers/place_handler.dart |
| FeedbackHandler | (pre-existing) | lib/api/handlers/feedback_handler.dart |
| **Total** | **~316 lines** | |

---

## Remaining Phases

### Phase 4: Adopt Security Mixins

**Goal:** Make PureStationServer use `RateLimitMixin` and `HealthWatchdogMixin` fully.

**Complexity:** Medium | **Risk:** Medium | **Impact:** ~250 lines removed

#### 4.1 Adopt RateLimitMixin

**Current duplication in pure_station.dart (lines 10376-10518):**
```
_isIpBanned()        → isIpBanned()         [mixin]
_checkRateLimit()    → checkRateLimit()     [mixin]
_banIp()             → banIp()              [mixin]
_incrementConnection() → incrementConnection() [mixin]
_decrementConnection() → decrementConnection() [mixin]
_cleanupExpiredBans()  → cleanupExpiredBans()  [mixin]
_loadSecurityLists()   → loadSecurityLists()   [mixin]
```

**Steps:**
1. Change class declaration: `class PureStationServer with RateLimitMixin`
2. Add required abstract implementations:
   - `void log(String level, String message)` → delegate to `_log`
   - `String? get dataDir` → return `_dataDir`
3. Replace all internal calls (e.g., `_checkRateLimit` → `checkRateLimit`)
4. Remove duplicate methods (lines 10376-10518, ~142 lines)
5. Remove duplicate fields (`_bannedIps`, `_banExpiry`, `_permanentBlacklist`, `_whitelist`)

**Verification:** `flutter analyze lib/cli/pure_station.dart`

#### 4.2 Adopt HealthWatchdogMixin

**Current duplication in pure_station.dart (lines 1757-1865):**
```
_performHealthCheck()  → _performHealthCheck() [mixin, private]
_startHealthWatchdog() → startHealthWatchdog() [mixin]
_stopHealthWatchdog()  → stopHealthWatchdog()  [mixin]
_runHealthWatchdog()   → _runHealthWatchdog()  [mixin, private]
_detectAttack()        → _detectAttack()       [mixin, private]
_autoRecover()         → autoRecover()         [mixin, abstract]
```

**Steps:**
1. Add `HealthWatchdogMixin` to class declaration
2. Implement required abstract methods:
   - `int get httpPort` → return `_settings.httpPort`
   - `bool get isServerRunning` → return `_running`
   - `int get connectedClientsCount` → return `_clients.length`
   - `Future<void> autoRecover()` → delegate to existing `_autoRecover`
   - `void logCrash(String reason)` → delegate to existing `_logCrash`
3. Replace internal calls to use mixin methods
4. Remove duplicate methods (~108 lines)
5. Remove duplicate fields (`_healthWatchdogTimer`, `_consecutiveFailures`, etc.)

**Verification:** `flutter analyze lib/cli/pure_station.dart`

---

### Phase 5: Extract HTTP Handlers to Shared Modules

**Goal:** Move common HTTP handlers to `lib/server/handlers/` for reuse.

**Complexity:** Low | **Risk:** Low | **Impact:** ~300 lines shared

#### 5.1 Create ChatHandler

**Location:** `lib/server/handlers/chat_handler.dart`

Extract from pure_station.dart:
- `_handleChatRooms()` (line 9058)
- `_handleRoomMessages()` (line 9097)
- `_handleRoomMessageReactions()` (line 9214)
- `_handleChatFileUpload()` (line 9398)
- `_handleChatFilesList()` (line 9325)
- `_handleChatFileDownload()` (line 9504)
- `_handleChatFileContent()` (line 9583)

**Shared by:** PureStationServer, future CliStationServer chat support

#### 5.2 Create EmailHandler

**Location:** `lib/server/handlers/email_handler.dart`

Extract from pure_station.dart:
- `_handleEmailQueue()` (line 5217)
- `_handleEmailApprove()` (line 5259)
- `_handleEmailReject()` (line 5299)
- `_handleEmailAllowlist()` (line 5349)
- `_handleEmailSend()` (line 3157)
- `_handleIncomingEmail()` (line 3204)

**Shared by:** PureStationServer, SmtpMixin

#### 5.3 Consolidate Existing Handlers

**StatusHandler** - already exists, verify pure_station uses it:
- Compare `_handleStatus()` in pure_station.dart (line 5918) vs handlers/status_handler.dart

**BlossomHandler** - already exists, verify pure_station uses it:
- Compare `_handleBlossomRequest/Upload/Download()` vs handlers/blossom_handler.dart

**TileHandler** - already exists, verify pure_station uses it:
- Compare `_handleTileRequest()` vs handlers/tile_handler.dart

---

### Phase 6: Extract Update/Model Mirroring

**Goal:** Move update and AI model mirroring to shared modules.

**Complexity:** Medium | **Risk:** Low | **Impact:** ~600 lines shared

#### 6.1 Create UpdateMirrorService

**Location:** `lib/services/update_mirror_service.dart`

Extract from pure_station.dart:
- `_loadCachedRelease()` / `_saveCachedRelease()`
- `_startUpdatePolling()` / `_pollForUpdates()`
- `_downloadGitHubRelease()` / `_downloadBinary()`
- `_buildAssetUrls()` / `_buildAssetFilenames()`

#### 6.2 Create WhisperMirrorService

**Location:** `lib/services/whisper_mirror_service.dart`

Extract from pure_station.dart:
- `_downloadAllWhisperModels()`
- `_scanExistingWhisperModels()`
- `_getAvailableWhisperModels()`
- Whisper model definitions (lines 10843-10881)

#### 6.3 Create SupertonicMirrorService

**Location:** `lib/services/supertonic_mirror_service.dart`

Extract from pure_station.dart:
- `_downloadAllSupertonicModels()`
- `_scanExistingSupertonicModels()`
- `_getAvailableSupertonicModels()`
- Supertonic model definitions (lines 11001-11117)

---

### Phase 7: Extract SSL/Certificate Management

**Goal:** Consolidate SSL handling between PureStationServer and SslMixin.

**Complexity:** High | **Risk:** Medium | **Impact:** ~500 lines shared

#### 7.1 Analyze Current Duplication

**PureStationServer SSL code (lines 11326-12124):**
- `_initSslDirectory()`
- `_startAutoRenewal()` / `_stopAutoRenewal()`
- `_checkCertificateValid()`
- `_getCertificateInfo()` / `_getCertificateExpiry()`
- `_checkAndRenewIfNeeded()`
- `_requestCertificate()` / `_renewCertificate()`
- `_requestCertificateNative()` - Native ACME implementation
- ACME protocol methods (directory, account, order, challenge, finalize)
- `_generateSelfSignedCertificate()`

**SslMixin (lib/server/mixins/ssl_mixin.dart):**
- Similar but may have different implementation

#### 7.2 Consolidate to SslMixin

Either:
A. Make PureStationServer use SslMixin (requires class restructuring)
B. Extract shared SSL utilities to `lib/util/ssl_utils.dart`

---

### Phase 8: WebSocket Message Handling Consolidation

**Goal:** Unify WebSocket message routing between implementations.

**Complexity:** Medium | **Risk:** Medium | **Impact:** ~200 lines shared

#### 8.1 Create WebSocketMessageRouter

**Location:** `lib/server/websocket_router.dart`

Extract common message handling:
- HELLO message processing
- PING/PONG handling
- HTTP_RESPONSE routing
- BACKUP_PROVIDER_ANNOUNCE
- Standard message types

#### 8.2 Platform-Specific Extensions

Keep platform-specific handlers in respective implementations:
- WebRTC signaling (PureStationServer only)
- Email send (PureStationServer only)
- NOSTR event handling (shared)

---

## Implementation Priority

| Phase | Priority | Effort | Risk | Lines Saved |
|-------|----------|--------|------|-------------|
| **Phase 4** | High | Medium | Medium | ~250 |
| **Phase 5.3** | High | Low | Low | ~100 |
| **Phase 5.1** | Medium | Medium | Low | ~200 |
| **Phase 6** | Medium | Medium | Low | ~600 |
| **Phase 5.2** | Low | Low | Low | ~150 |
| **Phase 7** | Low | High | Medium | ~500 |
| **Phase 8** | Low | Medium | Medium | ~200 |

**Recommended order:** 4 → 5.3 → 5.1 → 6 → 5.2 → 8 → 7

---

## Success Metrics

| Metric | Before | Target |
|--------|--------|--------|
| pure_station.dart lines | 12,136 | < 10,000 |
| Duplicate code instances | ~15 | < 5 |
| Shared utility files | 9 | 15+ |
| Test coverage for shared code | Unknown | > 80% |

---

## Risks and Mitigations

1. **Breaking existing CLI functionality**
   - Mitigation: Run full test suite after each phase
   - Mitigation: Keep feature flags for rollback

2. **Mixin conflicts with existing fields**
   - Mitigation: Rename private fields before adding mixins
   - Mitigation: Use composition pattern if mixins don't fit

3. **Different behavior between implementations**
   - Mitigation: Document differences before consolidating
   - Mitigation: Add configuration options for platform-specific behavior

---

## Files to Create

```
lib/server/handlers/
├── chat_handler.dart        # Phase 5.1
└── email_handler.dart       # Phase 5.2

lib/services/
├── update_mirror_service.dart    # Phase 6.1
├── whisper_mirror_service.dart   # Phase 6.2
└── supertonic_mirror_service.dart # Phase 6.3

lib/server/
└── websocket_router.dart    # Phase 8.1

lib/util/
└── ssl_utils.dart           # Phase 7.2 (if needed)
```

## Files to Modify

- `lib/cli/pure_station.dart` - All phases
- `lib/server/station_server_base.dart` - Phases 5, 8
- `lib/server/cli_station_server.dart` - Phases 4, 5, 6
- `docs/reusable.md` - Document new shared components
