# Encrypted Archive - Dart Package Specification

## Overview

A high-performance encrypted archive format using SQLite as the storage backend. Designed for:

- **Streaming**: Read/write without loading entire files into memory
- **Incremental updates**: Modify individual files without rewriting the entire archive
- **Scale**: Support for terabyte-scale archives (hundreds of TB)
- **Security**: AES-256-GCM encryption with Argon2id key derivation
- **Deduplication**: Optional content-addressed chunk deduplication
- **Compression**: Optional per-chunk compression (gzip, zstd, lz4)

File extension: `.ear` (Encrypted ARchive)

---

## Architecture

### Storage Model

```
┌─────────────────────────────────────────────────────────┐
│                    SQLite Database                       │
├─────────────────────────────────────────────────────────┤
│  archive_header    │ Salt, verification hash, options   │
├────────────────────┼────────────────────────────────────┤
│  files             │ Metadata, paths, encryption nonces │
├────────────────────┼────────────────────────────────────┤
│  chunks            │ Encrypted data blobs (≤64MB each)  │
├────────────────────┼────────────────────────────────────┤
│  dedup_refs        │ Content-addressed chunk references │
├────────────────────┼────────────────────────────────────┤
│  archive_stats     │ Cached statistics, maintenance log │
└─────────────────────────────────────────────────────────┘
```

### Encryption Hierarchy

```
Password
    │
    ▼ Argon2id (salt, time_cost, memory_cost, parallelism)
    │
┌───┴───────────────────────────────────────┐
│         Master Key Material (128 bytes)    │
├───────────────┬───────────────┬───────────┤
│  Master Key   │ Metadata Key  │ Auth Key  │ + Verification Hash
│   (32 bytes)  │  (32 bytes)   │ (32 bytes)│     (32 bytes)
└───────┬───────┴───────────────┴───────────┘
        │
        ▼ HKDF-SHA256 (file_id as info)
        │
    File Key
        │
        ▼ AES-256-GCM (nonce = file_nonce || chunk_sequence)
        │
    Encrypted Chunk
```

### Chunk Nonce Derivation

Each chunk gets a unique 12-byte nonce:
- Bytes 0-7: First 8 bytes of file's random nonce
- Bytes 8-11: Chunk sequence number (little-endian uint32)

This ensures no nonce reuse even across billions of chunks.

---

## Database Schema

### Table: `archive_header`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Always 1 (singleton) |
| magic | TEXT | "EARCH01" - format identifier |
| schema_version | INTEGER | Current: 1 |
| created_at | INTEGER | Unix timestamp ms |
| salt | BLOB(32) | Argon2id salt |
| verification_hash | BLOB(32) | For password verification |
| options_json | TEXT | Serialized ArchiveOptions |
| description | TEXT | Optional user description |

### Table: `files`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment |
| path | TEXT NOT NULL | Forward-slash separated path |
| type | INTEGER | 0=file, 1=directory, 2=symlink |
| size | INTEGER | Uncompressed size in bytes |
| stored_size | INTEGER | Compressed+encrypted size |
| created_at | INTEGER | Unix timestamp ms |
| modified_at | INTEGER | Unix timestamp ms |
| content_hash | BLOB(32) | SHA-256 of uncompressed content |
| encryption_nonce | BLOB(12) | Random per-file nonce |
| chunk_count | INTEGER | Number of chunks |
| permissions | INTEGER | POSIX mode (optional) |
| symlink_target | TEXT | For symlinks only |
| metadata_json | TEXT | Custom key-value pairs |
| deleted | INTEGER | 0=active, 1=soft-deleted |

**Indexes:**
- `UNIQUE INDEX idx_files_path ON files(path) WHERE deleted = 0`
- `INDEX idx_files_parent ON files(path) WHERE deleted = 0`

### Table: `chunks`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment |
| file_id | INTEGER | FK to files.id |
| sequence | INTEGER | 0-based chunk index |
| size_plain | INTEGER | Uncompressed chunk size |
| size_stored | INTEGER | Size after compression |
| compression | INTEGER | CompressionType enum value |
| data | BLOB | Encrypted chunk data |
| auth_tag | BLOB(16) | AES-GCM authentication tag |
| content_hash | BLOB(32) | SHA-256 of plaintext (for dedup) |

**Constraints:**
- `FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE`
- `UNIQUE (file_id, sequence)`

**Indexes:**
- `INDEX idx_chunks_file_seq ON chunks(file_id, sequence)`

### Table: `dedup_refs` (Optional)

| Column | Type | Description |
|--------|------|-------------|
| content_hash | BLOB(32) PRIMARY KEY | SHA-256 of plaintext chunk |
| chunk_id | INTEGER | FK to canonical chunk |
| ref_count | INTEGER | Number of references |

### Table: `archive_stats`

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Always 1 (singleton) |
| total_files | INTEGER | Active file count |
| total_size | INTEGER | Sum of uncompressed sizes |
| total_stored_size | INTEGER | Sum of stored sizes |
| total_chunks | INTEGER | Chunk count |
| dedup_savings | INTEGER | Bytes saved by dedup |
| last_vacuum_at | INTEGER | Last vacuum timestamp |
| last_integrity_check_at | INTEGER | Last verify timestamp |

**Triggers:**
- Update stats on file insert/soft-delete
- Update stats on chunk insert/delete

---

## Public API

### Class: `EncryptedArchive`

```dart
class EncryptedArchive {
  // Factory constructors
  static Future<EncryptedArchive> create(
    String path,
    String password, {
    ArchiveOptions options = ArchiveOptions.defaultOptions,
    String? description,
  });

  static Future<EncryptedArchive> open(
    String path,
    String password, {
    ArchiveOptions? optionsOverride,
  });

  // Properties
  ArchiveOptions get options;
  bool get isClosed;

  // Write operations
  Future<ArchiveEntry> addFile(
    String path,
    Stream<List<int>> content, {
    int? size,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? permissions,
    Map<String, String>? metadata,
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });

  Future<ArchiveEntry> addFileFromDisk(
    String archivePath,
    String diskPath, {
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });

  Future<ArchiveEntry> addBytes(
    String path,
    List<int> bytes, {
    DateTime? createdAt,
    DateTime? modifiedAt,
    Map<String, String>? metadata,
  });

  Future<void> addDirectory(String path);

  Future<void> delete(String path);

  Future<void> rename(String oldPath, String newPath);

  // Read operations
  Stream<Uint8List> readFile(
    String path, {
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });

  Future<Uint8List> readFileBytes(String path);

  Future<void> extractFile(
    String archivePath,
    String diskPath, {
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });

  Future<void> extractAll(
    String outputDir, {
    String? prefix,
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });

  // Query operations
  Future<bool> exists(String path);
  Future<ArchiveEntry> getEntry(String path);
  Future<List<ArchiveEntry>> listFiles({String? prefix, bool includeDeleted});
  Future<ArchiveStats> getStats();

  // Maintenance
  Future<int> vacuum({ProgressCallback? onProgress});
  Future<List<IntegrityError>> verifyIntegrity({
    ProgressCallback? onProgress,
    CancellationToken? cancellation,
  });
  Future<void> changePassword(String oldPassword, String newPassword);

  // Lifecycle
  Future<void> close();
}
```

### Class: `ArchiveOptions`

```dart
class ArchiveOptions {
  final int chunkSize;              // Default: 16 MB
  final CompressionType compression; // Default: none
  final int compressionLevel;        // Default: 3
  final bool enableDeduplication;    // Default: false
  final bool enableWAL;              // Default: true
  final int pageSize;                // Default: 32768
  final int cacheSize;               // Default: -64000 (64 MB)
  final int mmapSize;                // Default: 0
  final int argon2TimeCost;          // Default: 3
  final int argon2MemoryCost;        // Default: 65536 (64 MB)
  final int argon2Parallelism;       // Default: 1

  // Presets
  static const defaultOptions;
  static const largeFileOptions;
  static const manySmallFilesOptions;
  static const highSecurityOptions;
}
```

### Class: `ArchiveEntry`

```dart
class ArchiveEntry {
  final int id;
  final String path;
  final ArchiveEntryType type;
  final int size;
  final int storedSize;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final Uint8List? contentHash;
  final int chunkCount;
  final int? permissions;
  final String? symlinkTarget;
  final Map<String, String>? metadata;

  // Computed
  String get name;
  String get parentPath;
  String get extension;
  double get compressionRatio;
  int get spaceSaved;
  bool get isFile;
  bool get isDirectory;
  bool get isSymlink;
}
```

### Enums

```dart
enum ArchiveEntryType { file, directory, symlink }
enum CompressionType { none, gzip, lz4, zstd }
enum ChunkSize { small(1MB), medium(16MB), large(64MB), xlarge(256MB) }
```

### Progress & Cancellation

```dart
class OperationProgress {
  final int bytesProcessed;
  final int? totalBytes;
  final int itemsProcessed;
  final int? totalItems;
  final String? currentOperation;
  final int? estimatedMsRemaining;

  double? get fraction;
  int? get percent;
  String toDisplayString();
}

typedef ProgressCallback = bool Function(OperationProgress progress);

class CancellationToken {
  bool get isCancelled;
  void cancel();
  void throwIfCancelled();
}
```

### Exceptions

```dart
sealed class ArchiveException implements Exception { ... }

class ArchiveOpenException extends ArchiveException { ... }
class ArchiveCorruptedException extends ArchiveException { ... }
class ArchiveCryptoException extends ArchiveException { ... }
class ArchiveAuthenticationException extends ArchiveException { ... }
class EntryNotFoundException extends ArchiveException { ... }
class EntryExistsException extends ArchiveException { ... }
class ArchiveIOException extends ArchiveException { ... }
class ArchiveClosedException extends ArchiveException { ... }
class OperationCancelledException extends ArchiveException { ... }
class IntegrityException extends ArchiveException { ... }
```

---

## Dependencies

```yaml
dependencies:
  sqlite3: ^2.4.0           # SQLite bindings via FFI
  cryptography: ^2.7.0      # AES-GCM, Argon2id, HKDF
  crypto: ^3.0.3            # SHA-256 hashing
  archive: ^3.4.0           # Compression algorithms
  meta: ^1.9.0              # Annotations
  path: ^1.8.0              # Path manipulation

dev_dependencies:
  test: ^1.24.0
  lints: ^3.0.0
  benchmark_harness: ^2.2.0
```

---

## Implementation Notes

### SQLite Configuration

```sql
PRAGMA page_size = 32768;       -- 32 KB pages for large BLOBs
PRAGMA journal_mode = WAL;      -- Write-ahead logging
PRAGMA synchronous = NORMAL;    -- Balance safety/speed
PRAGMA cache_size = -64000;     -- 64 MB cache
PRAGMA temp_store = MEMORY;
PRAGMA foreign_keys = ON;
```

### Incremental BLOB I/O

For chunks larger than available memory, use SQLite's incremental blob API:

```dart
final blob = db.openBlob('chunks', 'data', rowId, readOnly: true);
// Read in 64KB blocks
final buffer = Uint8List(65536);
while (offset < blob.length) {
  blob.read(buffer, offset);
  // Process...
}
blob.close();
```

### Streaming Chunker

Split input streams into fixed-size chunks without buffering entire file:

```dart
Stream<Uint8List> chunkStream(Stream<List<int>> source, int chunkSize) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final data in source) {
    buffer.add(data);
    while (buffer.length >= chunkSize) {
      final bytes = buffer.takeBytes();
      yield Uint8List.sublistView(bytes, 0, chunkSize);
      if (bytes.length > chunkSize) {
        buffer.add(bytes.sublist(chunkSize));
      }
    }
  }
  if (buffer.isNotEmpty) yield buffer.toBytes();
}
```

### Deduplication Strategy

When `enableDeduplication` is true:

1. Compute SHA-256 of plaintext chunk before encryption
2. Check `dedup_refs` for existing chunk with same hash
3. If found: increment `ref_count`, reference existing chunk
4. If not found: encrypt and store new chunk, add to `dedup_refs`
5. On delete: decrement `ref_count`, delete chunk only when count reaches 0

### Password Change

1. Derive new keys from new password
2. Re-encrypt all file nonces with new metadata key
3. Update `archive_header` with new salt and verification hash
4. Note: Chunk data doesn't need re-encryption (still encrypted with same master key structure)

Actually, for proper password change:
1. Derive new keys
2. Re-derive all file keys and re-encrypt all chunks (expensive!)
3. Or: Store an encrypted "archive key" that wraps the actual master key, only re-wrap on password change

**Recommended approach:** Store encrypted archive master key in header, wrap with password-derived key. Password change only re-wraps the master key.

---

## Project Structure

```
encrypted_archive/
├── pubspec.yaml
├── lib/
│   ├── encrypted_archive.dart      # Main library export
│   └── src/
│       ├── archive.dart            # EncryptedArchive class
│       ├── entry.dart              # ArchiveEntry, ChunkInfo
│       ├── options.dart            # ArchiveOptions, enums
│       ├── key_derivation.dart     # Argon2id, HKDF, nonce generation
│       ├── compression.dart        # Compression utilities
│       ├── schema.dart             # Database schema, migrations
│       ├── progress.dart           # ProgressCallback, CancellationToken
│       └── exceptions.dart         # All exception types
├── test/
│   ├── archive_test.dart
│   ├── encryption_test.dart
│   ├── compression_test.dart
│   └── large_file_test.dart
├── example/
│   └── example.dart
└── README.md
```

---

## Test Cases

1. **Basic operations**: Create, add file, read file, close, reopen, read again
2. **Wrong password**: Verify `ArchiveAuthenticationException` is thrown
3. **Large file streaming**: Add 1GB file, verify memory usage stays bounded
4. **Compression**: Verify compressed size < original for compressible data
5. **Deduplication**: Add same file twice, verify storage only increases by metadata
6. **Integrity**: Corrupt a chunk byte, verify `verifyIntegrity()` catches it
7. **Concurrent reads**: Multiple `readFile()` streams simultaneously
8. **Cancellation**: Cancel mid-operation, verify clean state
9. **Vacuum**: Delete files, vacuum, verify space reclaimed
10. **Path normalization**: Various path formats all resolve correctly
11. **Unicode paths**: Files with non-ASCII names
12. **Empty files**: Zero-byte files handled correctly
13. **Metadata**: Custom metadata preserved across close/reopen

---

## Future Considerations

- **Multi-volume**: Split archive across multiple files
- **Encryption algorithms**: ChaCha20-Poly1305 as alternative to AES-GCM
- **Remote storage**: Abstract storage backend (S3, SFTP, etc.)
- **Partial extraction**: Extract byte ranges without full chunk decryption
- **Encryption at rest**: SQLCipher integration for full database encryption
- **NOSTR signing**: Sign archive manifest with NOSTR keys for authenticity
