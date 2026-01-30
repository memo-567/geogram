# Encrypted Storage - Full Abstraction Layer

## Overview

This plan implements a `ProfileStorage` abstraction layer that allows services to read/write files transparently, whether the profile uses filesystem storage or encrypted SQLite archive storage.

## Progress Summary

### Phase 1: Core Abstraction - COMPLETED

Created `lib/services/profile_storage.dart` with:
- `ProfileStorage` abstract class defining the storage interface
- `FilesystemProfileStorage` implementation wrapping direct `File()` and `Directory()` operations
- `EncryptedProfileStorage` implementation wrapping `EncryptedStorageService` for SQLite-based encrypted archive
- `StorageEntry` model for directory listings

### Phase 2: CollectionService Migration - COMPLETED

Migrated all CollectionService methods to use the storage abstraction:

**Read Operations:**
- `loadCollectionsStream()` - streams collections from storage
- `_loadCollectionFromStorage()` - loads individual collection metadata
- `_loadSecuritySettingsFromStorage()` - loads security settings

**Write Operations:**
- `createCollection()` - creates new collections using storage abstraction
- `deleteCollection()` - removes collections from storage
- `updateCollection()` - updates collection metadata

**Collection Type Initializers:**
- `_initializeChatCollectionWithStorage()`
- `_initializeForumCollectionWithStorage()`
- `_initializePostcardsCollectionWithStorage()`
- `_initializeContactsCollectionWithStorage()`
- `_initializePlacesCollectionWithStorage()`
- `_initializeGroupsCollectionWithStorage()`
- `_initializeRelayCollectionWithStorage()`
- `_initializeConsoleCollectionWithStorage()`

**Utility Methods:**
- `_createSkeletonFilesWithStorage()`
- `_generateAndSaveTreeJsonWithStorage()`
- `_generateAndSaveDataJsWithStorage()`
- `_generateAndSaveIndexHtmlWithStorage()`
- `_writeCollectionFilesWithStorage()`

### Initialization Flow - COMPLETED

The storage abstraction is initialized in the correct order:
1. `main.dart` calls `setNsec()` before `setActiveCallsign()`
2. `profile_service.dart` calls `setNsec()` in `switchToProfile()`
3. `console.dart` calls `setNsec()` for CLI mode

### Performance Optimization - COMPLETED

**Problem:** Initial panel loading was extremely slow (minutes) because the encrypted archive was being opened/closed for every single file operation.

**Solution:** Implemented singleton pattern with persistent archive connections:
- `_openArchives` map caches open archive connections by callsign
- `_getArchive()` returns cached or opens new connection
- `closeArchive()` cleans up when switching profiles
- `closeAllArchives()` cleans up on app shutdown
- Periodic flush (30 second WAL checkpoint) reduces data loss on crash

**Files Modified:**
- `lib/services/encrypted_storage_service.dart` - singleton pattern + periodic flush
- `lib/services/profile_service.dart` - calls `closeArchive()` on profile switch
- `lib/main.dart` - calls `closeAllArchives()` on app dispose
- `packages/encrypted_archive/lib/src/archive.dart` - added `checkpoint()` method

---

## Phase 3: Migrate Individual Services - IN PROGRESS

### ChatService - MIGRATED (Core Methods)

Migrated methods:
- `createChannel()` - directory creation with ProfileStorage
- `deleteChannel()` - directory deletion with ProfileStorage
- `saveMessage()` - message appending with read-append-write pattern
- `loadMessages()` - channel existence check with ProfileStorage
- `_loadMainChannelMessagesStorage()` - NEW: loads daily files from year folders
- `_loadSingleFileMessagesStorage()` - NEW: loads single messages.txt
- `_getDailyMessageFilePathStorage()` - NEW: creates year folder structure

Remaining (lower priority - edit/delete operations):
- `editMessage()`, `deleteMessageByTimestamp()`, `toggleReaction()` - need migration
- `findMessage()` - needs migration
- File watching (not applicable to encrypted storage)

### ContactService - MIGRATED (Core Methods)

Migrated methods:
- `saveContact()` - file writing with ProfileStorage
- `deleteContact()` - file deletion with ProfileStorage
- `_getRelativePath()` - NEW helper for path conversion

Already had ProfileStorage support:
- `initializeCollection()` - directory creation
- `loadContactSummaries()` - read operations
- `loadContactFromRelativePath()` - read operations
- `_loadContactFilesBySearchPath()` - directory listing

Remaining (lower priority - group operations):
- `moveContactToGroup()` - file move operations
- `deleteGroup()`, `deleteGroupWithContacts()` - group deletion

### Other Services - PENDING

| Service | Priority | Key Methods to Migrate |
|---------|----------|----------------------|
| BlogService | Medium | loadPosts, savePost, deletePost |
| EventService | Medium | loadEvents, saveEvent, deleteEvent |
| PlaceService | Medium | loadPlaces, savePlace, deletePlace |
| GroupsService | Medium | loadGroups, saveGroup |
| ForumService | Medium | loadThreads, saveThread |
| DirectMessageService | Low | loadConversations, saveMessage |
| ConsoleService | Low | loadSessions |

---

## Migration Pattern

For each service method that reads/writes files:

### Before (direct filesystem)
```dart
final file = File('$collectionPath/data.json');
if (await file.exists()) {
  final content = await file.readAsString();
}
```

### After (storage abstraction)
```dart
if (_storage != null) {
  final content = await _storage!.readString('data.json');
  if (content != null) {
    // process content
  }
} else {
  // Fallback to direct filesystem
  final file = File('$collectionPath/data.json');
  if (await file.exists()) {
    final content = await file.readAsString();
  }
}
```

### Key Methods to Use

| Operation | ProfileStorage Method |
|-----------|----------------------|
| Read file | `readString(relativePath)` |
| Read bytes | `readBytes(relativePath)` |
| Write file | `writeString(relativePath, content)` |
| Write bytes | `writeBytes(relativePath, bytes)` |
| Check exists | `exists(relativePath)` |
| Delete file | `delete(relativePath)` |
| Create directory | `createDirectory(relativePath)` |
| Delete directory | `deleteDirectory(relativePath, recursive: true)` |
| List directory | `listDirectory(relativePath)` |

---

## Implementation Steps for Each Service

1. **Identify all filesystem operations** in the service
2. **Migrate read operations first** (loading data)
3. **Then migrate write operations** (saving data)
4. **Add fallback paths** for when `_storage` is null
5. **Test with encrypted profile** to verify

---

## Verification Checklist

After migrating each service:

1. Launch app with encrypted profile
2. Verify service can load existing data
3. Create new data and verify it's saved
4. Restart app and verify data persists
5. Check encrypted archive contains the data

### Service-Specific Tests

- **ChatService**: Load channels, send/receive messages, verify history
- **ContactService**: Load/save/delete contacts, verify relay list
- **BlogService**: Load/create/edit/delete posts
- **EventService**: Load/create/edit events
- **PlaceService**: Load/save/delete places
- **GroupsService**: Load/create groups
- **ForumService**: Load/create threads and posts
- **DirectMessageService**: Load conversations, send messages

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Service Layer                          │
│  (ChatService, ContactService, BlogService, etc.)          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   ProfileStorage                            │
│                  (Abstract Class)                           │
│  - readString, writeString                                  │
│  - readBytes, writeBytes                                    │
│  - exists, delete                                           │
│  - createDirectory, deleteDirectory, listDirectory          │
└──────────────────────────┬──────────────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           │                               │
           ▼                               ▼
┌──────────────────────┐     ┌──────────────────────────────┐
│ FilesystemProfile    │     │ EncryptedProfileStorage      │
│ Storage              │     │                              │
│ (Direct File I/O)    │     │ (SQLite Archive via          │
│                      │     │  EncryptedStorageService)    │
└──────────────────────┘     └──────────────────────────────┘
```

---

## Files Modified

### Phase 1
- `lib/services/profile_storage.dart` (NEW)

### Phase 2
- `lib/services/collection_service.dart`
- `lib/main.dart`
- `lib/services/profile_service.dart`
- `lib/cli/console.dart`

### Phase 3 (Pending)
- `lib/services/chat_service.dart`
- `lib/services/contact_service.dart`
- `lib/services/blog_service.dart`
- `lib/services/event_service.dart`
- `lib/services/place_service.dart`
- `lib/services/groups_service.dart`
- `lib/services/forum_service.dart`
- `lib/services/direct_message_service.dart`
- `lib/services/console_service.dart`
