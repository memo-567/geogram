# Geogram Story Music Collection

A curated collection of **21 CC0 public domain** music tracks for use as background music in Geogram Stories.

## Features

- **License**: CC0 1.0 (Public Domain) - No attribution required
- **Total Size**: ~29 MB (fits within 30 MB limit)
- **Offline-First**: Works without internet connection
- **Diverse Genres**: 8 categories covering various moods

## Categories

| Category | Tracks | Best For |
|----------|--------|----------|
| Acoustic | 1 | Personal, warm stories |
| Ambient | 3 | Atmospheric, mysterious moments |
| Chill | 2 | Relaxed, casual content |
| Cinematic | 7 | Dramatic reveals, transitions |
| Electronic | 1 | Tech, modern content |
| Jazz | 1 | Quirky, sophisticated moments |
| Upbeat | 4 | Happy, energetic stories |
| World | 2 | Travel, cultural content |

## Dart/Flutter Integration

```dart
// Example: Story music player integration
class StoryMusicService {
  static const String assetPath = 'assets/music/';
  
  static final Map<String, List<String>> categories = {
    'acoustic': ['guitar_interstitial.mp3'],
    'ambient': ['diablo.mp3', 'stratosphere.mp3', 'terminal.mp3'],
    'chill': ['downy_feathers.mp3', 'last_call.mp3'],
    'cinematic': ['epilogue.mp3', 'interluder.mp3', 'intro.mp3', 
                  'maestro.mp3', 'piano_cue.mp3', 'running_fanfare.mp3', 'sting.mp3'],
    'electronic': ['synth_short.mp3'],
    'jazz': ['jazz_hates_you.mp3'],
    'upbeat': ['beautiful_soup.mp3', 'dopey_stroll.mp3', 
               'here_we_go.mp3', 'pump_sting.mp3'],
    'world': ['bongo_flute.mp3', 'east_of_tunesia.mp3'],
  };
  
  String getTrackPath(String category, String filename) {
    return '$assetPath$category/$filename';
  }
}
```

## pubspec.yaml

```yaml
flutter:
  assets:
    - assets/music/acoustic/
    - assets/music/ambient/
    - assets/music/chill/
    - assets/music/cinematic/
    - assets/music/electronic/
    - assets/music/jazz/
    - assets/music/upbeat/
    - assets/music/world/
```

## Short Stings (< 30 seconds)

Ideal for transitions and notifications:
- `cinematic/piano_cue.mp3` - Emotional moment
- `cinematic/sting.mp3` - Attention grabber  
- `cinematic/running_fanfare.mp3` - Urgent/action
- `upbeat/pump_sting.mp3` - Exciting reveal
- `upbeat/dopey_stroll.mp3` - Playful loop
- `electronic/synth_short.mp3` - Tech vibe
- `jazz/jazz_hates_you.mp3` - Quirky moment
- `world/bongo_flute.mp3` - Tribal feel
- `acoustic/guitar_interstitial.mp3` - Warm transition

## Source

All tracks sourced from [FreePD.com](https://freepd.com) via [Internet Archive](https://archive.org/details/freepd).

## Expanding the Collection

The full FreePD archive contains **1000+ tracks (6.7 GB)** available at:
https://archive.org/details/freepd

Filter by file size to find more small tracks suitable for mobile.
