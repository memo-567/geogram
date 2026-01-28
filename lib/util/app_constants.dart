/// Pure Dart constants for app/collection types
/// This file has no Flutter dependencies so it can be used in CLI mode

/// All known app/collection types that can be routed to via URL
/// This is the canonical list used for URL routing and collection management
const List<String> knownAppTypesConst = [
  'www',
  'blog',
  'chat',
  'email',
  'forum',
  'events',
  'alerts',
  'places',
  'files',
  'contacts',
  'transfer',
  'groups',
  'news',
  'postcards',
  'market',
  'station',
  'documents',
  'photos',
  'inventory',
  'wallet',
  'log',
  'backup',
  'console',
  'tracker',
  'videos',
  'reader',
  'work',
];

/// App types that can only have a single instance per profile
/// Used by CreateCollectionPage to prevent duplicate creation
/// and by main.dart to show default apps
const Set<String> singleInstanceTypesConst = {
  'forum',
  'chat',
  'blog',
  'email',
  'events',
  'news',
  'www',
  'postcards',
  'places',
  'market',
  'alerts',
  'groups',
  'backup',
  'transfer',
  'inventory',
  'wallet',
  'log',
  'console',
  'tracker',
  'contacts',
  'videos',
  'reader',
  'flasher',
  'work',
};
