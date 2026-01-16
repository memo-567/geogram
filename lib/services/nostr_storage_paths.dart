/*
 * Platform-aware NOSTR storage paths.
 */

export 'nostr_storage_paths_pure.dart'
    if (dart.library.ui) 'nostr_storage_paths_flutter.dart';
