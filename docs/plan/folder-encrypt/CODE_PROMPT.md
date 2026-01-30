# Claude Code Implementation Prompt

## Task

Implement the `encrypted_archive` Dart package according to `SPECIFICATION.md`.

## Instructions

1. **Read the specification first** - Review `SPECIFICATION.md` thoroughly before writing any code.

2. **Project setup**
   - Create `pubspec.yaml` with all dependencies listed in the spec
   - Set up the directory structure as specified
   - Use Dart 3.0+ features (sealed classes, pattern matching, etc.)

3. **Implementation order**
   - Start with `exceptions.dart` (no dependencies)
   - Then `options.dart` (enums and configuration)
   - Then `progress.dart` (callbacks and cancellation)
   - Then `entry.dart` (data models)
   - Then `schema.dart` (database setup)
   - Then `key_derivation.dart` (crypto primitives)
   - Then `compression.dart` (compression utilities)
   - Finally `archive.dart` (main class, imports all others)
   - Last: `encrypted_archive.dart` (library exports)

4. **Key implementation details**

   **Encryption:**
   - Use `package:cryptography` for AES-GCM and Argon2id
   - Use `package:crypto` for SHA-256 hashing
   - Never reuse nonces - derive from file_nonce + chunk_sequence
   - Use constant-time comparison for verification hash

   **SQLite:**
   - Use `package:sqlite3` (FFI-based, not sqflite)
   - Configure pragmas before creating tables
   - Use transactions for multi-statement operations
   - Implement incremental BLOB I/O for large chunks

   **Streaming:**
   - Use `async*` generators for streaming reads
   - Implement chunk buffering without loading entire files
   - Support cancellation via CancellationToken
   - Report progress via callbacks

   **Error handling:**
   - Wrap all SQLite errors in appropriate ArchiveException subclasses
   - Rollback partial operations on failure
   - Clean up resources in finally blocks

5. **Code style**
   - Use `@immutable` annotation for value classes
   - Document all public APIs with `///` comments
   - Use named parameters for optional arguments
   - Prefer `const` constructors where possible
   - Follow Dart naming conventions (lowerCamelCase, UpperCamelCase)

6. **Testing**
   - Create comprehensive tests in `test/` directory
   - Test both success and failure paths
   - Test edge cases (empty files, large files, unicode paths)
   - Use temporary directories for test archives

7. **Example**
   - Create a runnable example in `example/example.dart`
   - Demonstrate: create, add files, list, read, extract, delete, vacuum

## Quality checklist

- [ ] All public classes and methods have documentation
- [ ] All exceptions are properly typed (no raw Exception throws)
- [ ] Resources are properly disposed (database, keys, blobs)
- [ ] Passwords/keys are cleared from memory when done
- [ ] No hardcoded test passwords in committed code
- [ ] Streaming operations don't load entire files into memory
- [ ] Progress callbacks can cancel operations
- [ ] Soft-delete preserves data until vacuum
- [ ] Statistics are updated via triggers (not manual counting)

## Don't forget

- The `archive` package is for compression algorithms, not the main archive logic
- SQLite BLOB max size is ~2GB, hence chunking is required
- Argon2id parameters should be configurable for different security/speed tradeoffs
- File paths should be normalized (forward slashes, no leading slash)
- The verification hash is for password checking, not data integrity
- WAL mode requires `synchronous = NORMAL`, not `FULL`

## Run commands

```bash
# Get dependencies
dart pub get

# Run tests
dart test

# Run example
dart run example/example.dart

# Analyze code
dart analyze

# Format code
dart format lib test example
```
