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
  'usenet',
  'music',
  'stories',
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
  'usenet',
  'music',
  'stories',
};

/// Predefined categories for stories
const List<String> storyCategoriesConst = [
  'news',
  'fun',
  'tech',
  'adult',
  'diary',
  'geocache',
  'travel',
  'tutorial',
  'gaming',
  'food',
  'fitness',
  'art',
  'music',
  'nature',
  'history',
  'science',
  'business',
  'family',
  'pets',
  'diy',
  'mystery',
  'romance',
  'horror',
  'fantasy',
];

/// Icon codes for story categories (Material Icons codepoints)
/// Use with: Icon(IconData(storyCategoryIconCodes['news']!, fontFamily: 'MaterialIcons'))
const Map<String, int> storyCategoryIconCodes = {
  'news': 0xe3e0, // newspaper
  'fun': 0xe166, // celebration
  'tech': 0xe30a, // computer
  'adult': 0xf06da, // no_adult_content
  'diary': 0xe3dd, // menu_book
  'geocache': 0xea15, // explore
  'travel': 0xe539, // flight
  'tutorial': 0xe80c, // school
  'gaming': 0xe1b9, // sports_esports
  'food': 0xe56c, // restaurant
  'fitness': 0xea68, // fitness_center
  'art': 0xe40a, // palette
  'music': 0xe3e7, // music_note
  'nature': 0xe53f, // park
  'history': 0xe8b5, // history_edu
  'science': 0xe561, // science
  'business': 0xe0af, // business
  'family': 0xe32f, // family_restroom
  'pets': 0xe91d, // pets
  'diy': 0xe3ce, // build
  'mystery': 0xf0674, // mystery
  'romance': 0xe25b, // favorite
  'horror': 0xf04bc, // skull (emoji_emotions as fallback)
  'fantasy': 0xea20, // auto_fix_high
};
