# Stories App - Format Specification

**Version:** 1.0.0
**Status:** Draft
**Document Format:** NDF (Nostr Data Format)

## Overview

The Stories app enables users to create interactive visual narratives. Each story is a self-contained NDF archive (`.ndf` ZIP file) containing scenes with positioned elements (images, text, buttons) and triggers that respond to user interaction or time events.

## Key Concepts

### Stories

A story is an interactive visual narrative with:
- Ordered scenes (similar to slides, but with interactivity)
- Elements positioned on each scene (images, text boxes, buttons)
- Triggers for navigation, URLs, or sounds
- Optional timed auto-advance between scenes

### Scenes

Each scene represents a single view in the story, containing:
- Background (image or solid color)
- Overlay elements with percentage-based positioning
- Touch triggers for user interaction
- Optional auto-advance timer with countdown display

### Elements

Visual components placed on scenes:
- **Image** - Pictures from assets, positioned and sized
- **Text** - Text boxes with styling (font, color, size)
- **Button** - Interactive areas with visual shapes or invisible

### Triggers

Actions that occur on user interaction or timer:
- **goToScene** - Navigate to another scene in the story
- **openUrl** - Open external URL in browser
- **playSound** - Play audio from assets

### Button Shapes

| Shape | Description |
|-------|-------------|
| `rectangle` | Rectangular button with sharp corners |
| `roundedRect` | Rectangle with rounded corners |
| `circle` | Circular button |
| `dot` | Small circular indicator with optional text label beside it |
| `invisible` | Invisible touch area (shown with red dotted border in Studio only) |

The `dot` shape is useful for creating small interactive points on an image with a text label. The `invisible` shape creates hidden hotspots for treasure hunting or secret interactions.

## NDF Archive Structure

Each story is a standalone `.ndf` file (ZIP archive). The filename is derived from the story title.

### Filename Convention

The filename is generated from the story title using these rules:

1. Convert to lowercase
2. Replace spaces with hyphens (`-`)
3. Remove invalid filesystem characters: `\ / : * ? " < > |`
4. Replace consecutive hyphens with single hyphen
5. Trim hyphens from start/end
6. Limit to 100 characters (to stay safe on all filesystems)
7. Add `.ndf` extension

**Examples:**

| Story Title | Filename |
|-------------|----------|
| My Adventure | `my-adventure.ndf` |
| The Forest: Part 1 | `the-forest-part-1.ndf` |
| João's Story | `joaos-story.ndf` |
| "Hello World!" | `hello-world.ndf` |

If a file with the same name already exists, append a number: `my-adventure-2.ndf`

```
my-adventure.ndf (ZIP archive)
│
├── ndf.json                    # Root metadata (REQUIRED)
├── permissions.json            # Ownership & signatures (REQUIRED)
├── index.html                  # Self-rendering viewer (RECOMMENDED)
│
├── content/
│   ├── main.json               # Story content (scenes, elements, triggers)
│   └── scenes/                 # Optional: one file per scene for large stories
│       ├── scene-001.json
│       └── scene-002.json
│
├── assets/
│   ├── logo.png                # Story branding logo (OPTIONAL)
│   ├── media/                  # All media files (images, audio)
│   │   ├── a1b2c3d4e5f6...abc.jpg    # SHA1 hash + original extension
│   │   ├── f6e5d4c3b2a1...def.png
│   │   └── 9876543210ab...ghi.mp3
│   └── thumbnails/
│       └── preview.png         # Story preview thumbnail (OPTIONAL)
│
├── social/
│   ├── reactions.json          # Likes, emoticons (signed)
│   └── comments.json           # Threaded comments (signed)
│
└── history/
    └── changes.json            # Edit history with signatures
```

When a story title is changed, the file is renamed accordingly. The internal `id` in `ndf.json` remains constant (UUID) for tracking purposes, but the filename always reflects the current title.

### Media File Naming Convention

All media files use SHA1 hash of the file content as filename, followed by the original extension:

```
SHA1(file_content) + "." + original_extension
```

Examples:
- `a1b2c3d4e5f6789012345678901234567890abcd.jpg`
- `f6e5d4c3b2a1098765432109876543210fedcba.png`
- `9876543210abcdef1234567890abcdef12345678.mp3`

This approach:
- Prevents duplicate files (same content = same hash = same filename)
- Allows safe file deduplication when merging stories
- Preserves original file type via extension

## ndf.json (Root Metadata)

The `title` field determines the filename on disk (e.g., `"My Adventure"` → `my-adventure.ndf`).

```json
{
  "ndf": "1.0.0",
  "type": "story",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "My Adventure",
  "description": "An interactive story about exploration",
  "logo": "asset://logo.png",
  "thumbnail": "asset://thumbnails/preview.png",
  "language": "en",
  "created": "2025-01-30T10:00:00Z",
  "modified": "2025-01-30T14:30:00Z",
  "revision": 5,
  "tags": ["adventure", "interactive", "kids"],
  "content_hash": "sha256:abc123...",
  "required_features": ["story_viewer"],
  "extensions": []
}
```

### Story-Specific Metadata Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Must be `"story"` |
| `id` | string | Yes | Internal UUID (remains constant, used for sync/tracking) |
| `title` | string | Yes | Display name (determines filename on disk) |
| `description` | string | No | Optional description |
| `logo` | string | No | Asset reference to logo |
| `thumbnail` | string | No | Asset reference to preview image |
| `language` | string | No | ISO 639-1 language code |
| `created` | ISO 8601 | Yes | Creation timestamp |
| `modified` | ISO 8601 | Yes | Last modification timestamp |
| `revision` | number | Yes | Revision counter |
| `tags` | array | No | Keywords for categorization |

## content/main.json (Story Content)

```json
{
  "type": "story",
  "schema": "ndf-story-1.0",
  "startSceneId": "scene-001",
  "settings": {
    "defaultTransition": "fade",
    "transitionDuration": 300,
    "showSceneTitle": false,
    "enableSwipeNavigation": true
  },
  "scenes": ["scene-001", "scene-002", "scene-003"]
}
```

### Settings Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `defaultTransition` | string | `"fade"` | Transition type: `fade`, `slide`, `none` |
| `transitionDuration` | number | `300` | Transition duration in milliseconds |
| `showSceneTitle` | boolean | `false` | Display scene titles |
| `enableSwipeNavigation` | boolean | `true` | Allow swipe gestures for navigation |
| `allowBackNavigation` | boolean | `true` | Allow users to go back to previous scene |

## content/scenes/scene-001.json (Scene Definition)

```json
{
  "id": "scene-001",
  "index": 0,
  "title": "Welcome",
  "allowBack": true,
  "background": {
    "type": "image",
    "asset": "asset://media/a1b2c3d4e5f6789012345678901234567890abcd.jpg",
    "appearAt": 0,
    "placeholder": "#1a1a2e"
  },
  "elements": [
    {
      "id": "elem-001",
      "type": "text",
      "appearAt": 1500,
      "position": {
        "anchor": "topCenter",
        "offsetX": 0,
        "offsetY": 10,
        "width": "large",
        "height": "auto"
      },
      "properties": {
        "text": "Welcome to the Forest",
        "fontSize": "title",
        "fontWeight": "bold",
        "color": "#FFFFFF",
        "align": "center",
        "backgroundColor": "rgba(0,0,0,0.5)"
      }
    },
    {
      "id": "elem-002",
      "type": "button",
      "appearAt": 3000,
      "position": {
        "anchor": "bottomCenter",
        "offsetX": 0,
        "offsetY": -15,
        "width": "medium",
        "height": "auto"
      },
      "properties": {
        "shape": "roundedRect",
        "label": "Begin Adventure",
        "backgroundColor": "#4CAF50",
        "textColor": "#FFFFFF"
      }
    }
  ],
  "triggers": [
    {
      "id": "trig-001",
      "type": "goToScene",
      "elementId": "elem-002",
      "targetSceneId": "scene-002"
    }
  ],
  "autoAdvance": null
}
```

**Timeline for this scene:**
| Time | Event |
|------|-------|
| 0ms | Scene starts, background image appears immediately |
| 1500ms | Title text fades in at top center |
| 3000ms | "Begin Adventure" button appears at bottom center |

### Scene Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique scene identifier |
| `index` | number | Yes | Scene order (0-based) |
| `title` | string | No | Scene title (shown if settings.showSceneTitle) |
| `allowBack` | boolean | No | Override global setting for back navigation on this scene |
| `background` | object | No | Background image or color |
| `elements` | array | No | List of positioned elements with appearance timing |
| `triggers` | array | No | List of interaction triggers |
| `autoAdvance` | object | No | Auto-advance configuration with countdown |

### Background Types

**Image background:**
```json
{
  "type": "image",
  "asset": "asset://media/sha1hash.jpg",
  "fit": "cover"
}
```

**Solid color background:**
```json
{
  "type": "color",
  "value": "#2E7D32"
}
```

### Scene Timing

All timing starts from when the scene is displayed (t=0). Every element, including the background, can have an appearance delay.

#### Background Timing

The background image can be delayed up to 5 seconds. While waiting, a solid color or previous scene is shown.

```json
{
  "background": {
    "type": "image",
    "asset": "asset://media/sha1hash.jpg",
    "appearAt": 2000,
    "placeholder": "#000000"
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appearAt` | number | `0` | Delay before background appears (0-5000ms) |
| `placeholder` | string | `"#000000"` | Color shown while waiting for background |

#### Element Timing

Each element has an `appearAt` property (milliseconds from scene start, 0-5000ms).

**Example timeline:**
| Time | Event |
|------|-------|
| 0ms | Scene starts, placeholder color shown |
| 500ms | Background image fades in (`appearAt: 500`) |
| 1500ms | Title text appears (`appearAt: 1500`) |
| 3000ms | Buttons appear (`appearAt: 3000`) |

Elements with the same `appearAt` value appear simultaneously. All timers are independent and count from scene start.

### Element Position (Anchor-Based)

Instead of exact pixel or percentage coordinates, elements use an **anchor-based positioning system** that adapts to any screen size and aspect ratio.

#### Anchor Points (9-point grid)

```
┌─────────────┬─────────────┬─────────────┐
│  topLeft    │  topCenter  │  topRight   │
├─────────────┼─────────────┼─────────────┤
│ centerLeft  │   center    │ centerRight │
├─────────────┼─────────────┼─────────────┤
│ bottomLeft  │bottomCenter │ bottomRight │
└─────────────┴─────────────┴─────────────┘
```

#### Position Object

```json
{
  "position": {
    "anchor": "bottomCenter",
    "offsetX": 0,
    "offsetY": -10,
    "width": "medium",
    "height": "auto"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `anchor` | string | Anchor point (see grid above) |
| `offsetX` | number | Horizontal offset from anchor (-50 to +50, percentage of screen) |
| `offsetY` | number | Vertical offset from anchor (-50 to +50, percentage of screen) |
| `width` | string/number | Size: `"small"`, `"medium"`, `"large"`, `"full"`, or number (0-100%) |
| `height` | string/number | Size: `"auto"`, `"small"`, `"medium"`, `"large"`, `"full"`, or number (0-100%) |

#### Predefined Sizes

| Size | Width | Typical Use |
|------|-------|-------------|
| `small` | 20% | Buttons, icons |
| `medium` | 40% | Text boxes, small images |
| `large` | 70% | Main content |
| `full` | 100% | Full-width elements |
| `auto` | Fit content | Text that wraps naturally |

#### Safe Zones

Elements automatically respect a **safe zone** (5% padding from screen edges) to prevent clipping on different devices. The `anchor` positions account for this:
- `topLeft` actually positions at (5%, 5%)
- `bottomRight` actually positions at (95%, 95%)

### Element Types

**Text Element:**
```json
{
  "id": "elem-001",
  "type": "text",
  "appearAt": 1500,
  "position": {
    "anchor": "topCenter",
    "offsetX": 0,
    "offsetY": 5,
    "width": "large",
    "height": "auto"
  },
  "properties": {
    "text": "Welcome to the Forest",
    "fontSize": "large",
    "fontWeight": "bold",
    "color": "#FFFFFF",
    "align": "center",
    "backgroundColor": "rgba(0,0,0,0.5)"
  }
}
```

Font sizes: `"small"` (14sp), `"medium"` (18sp), `"large"` (24sp), `"xlarge"` (32sp), `"title"` (48sp)

**Image Element (overlay):**
```json
{
  "id": "elem-002",
  "type": "image",
  "appearAt": 1000,
  "position": {
    "anchor": "center",
    "offsetX": 0,
    "offsetY": 0,
    "width": "medium",
    "height": "auto"
  },
  "properties": {
    "asset": "asset://media/sha1hash.png",
    "fit": "contain",
    "opacity": 1.0
  }
}
```

**Button Element:**
```json
{
  "id": "elem-003",
  "type": "button",
  "appearAt": 3000,
  "position": {
    "anchor": "bottomCenter",
    "offsetX": 0,
    "offsetY": -10,
    "width": "medium",
    "height": "auto"
  },
  "properties": {
    "shape": "roundedRect",
    "label": "Continue",
    "backgroundColor": "#4CAF50",
    "textColor": "#FFFFFF"
  }
}
```

**Multiple Buttons (side by side):**
```json
[
  {
    "id": "elem-left",
    "type": "button",
    "appearAt": 3000,
    "position": {
      "anchor": "bottomCenter",
      "offsetX": -25,
      "offsetY": -10,
      "width": "small",
      "height": "auto"
    },
    "properties": {
      "shape": "roundedRect",
      "label": "Go Left",
      "backgroundColor": "#2196F3",
      "textColor": "#FFFFFF"
    }
  },
  {
    "id": "elem-right",
    "type": "button",
    "appearAt": 3000,
    "position": {
      "anchor": "bottomCenter",
      "offsetX": 25,
      "offsetY": -10,
      "width": "small",
      "height": "auto"
    },
    "properties": {
      "shape": "roundedRect",
      "label": "Go Right",
      "backgroundColor": "#FF9800",
      "textColor": "#FFFFFF"
    }
  }
]
```

**Dot Button (small indicator with label):**
```json
{
  "id": "elem-004",
  "type": "button",
  "appearAt": 2000,
  "position": {
    "anchor": "center",
    "offsetX": -20,
    "offsetY": -15,
    "width": "auto",
    "height": "auto"
  },
  "properties": {
    "shape": "dot",
    "label": "Look here",
    "backgroundColor": "#FF5722",
    "textColor": "#FFFFFF",
    "labelPosition": "right"
  }
}
```

The `labelPosition` can be `"right"`, `"left"`, `"top"`, or `"bottom"`.

**Invisible Button (for treasure hunting):**
```json
{
  "id": "elem-005",
  "type": "button",
  "appearAt": 0,
  "position": {
    "anchor": "center",
    "offsetX": 10,
    "offsetY": 5,
    "width": "small",
    "height": "small"
  },
  "properties": {
    "shape": "invisible"
  }
}
```

Note: Invisible buttons are shown to the author in Studio mode with a red dotted border, but are completely invisible to end users. This is useful for treasure hunting or hidden interactions within images.

### Trigger Types

**goToScene - Navigate to another scene:**
```json
{
  "id": "trig-001",
  "type": "goToScene",
  "elementId": "elem-003",
  "targetSceneId": "scene-002"
}
```

**openUrl - Open external URL:**
```json
{
  "id": "trig-002",
  "type": "openUrl",
  "elementId": "elem-004",
  "url": "https://example.com"
}
```

**playSound - Play audio:**
```json
{
  "id": "trig-003",
  "type": "playSound",
  "elementId": "elem-005",
  "soundAsset": "asset://media/9876543210abcdef.mp3"
}
```

**Touch area trigger (no element):**

For touch areas without visible elements (e.g., "tap left side to go back, tap right side to continue"), use screen halves or quadrants:

```json
{
  "id": "trig-004",
  "type": "goToScene",
  "touchArea": "leftHalf",
  "targetSceneId": "scene-003"
}
```

Available touch areas:
| Area | Description |
|------|-------------|
| `leftHalf` | Left 50% of screen |
| `rightHalf` | Right 50% of screen |
| `topHalf` | Top 50% of screen |
| `bottomHalf` | Bottom 50% of screen |
| `topLeft` | Top-left quadrant (25%) |
| `topRight` | Top-right quadrant (25%) |
| `bottomLeft` | Bottom-left quadrant (25%) |
| `bottomRight` | Bottom-right quadrant (25%) |
| `center` | Center area (middle 50%) |

### Auto-Advance Configuration (Timed Trigger)

When a timed trigger is configured, a countdown is displayed in the **lower-right corner** of the scene. When the countdown reaches zero, the associated action is triggered.

```json
{
  "autoAdvance": {
    "delay": 15000,
    "targetSceneId": "scene-003",
    "showCountdown": true
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `delay` | number | Delay in milliseconds (1000-60000, i.e., 1-60 seconds) |
| `targetSceneId` | string | Scene to navigate to when countdown ends |
| `showCountdown` | boolean | Display countdown timer in lower-right corner |

The countdown displays the remaining seconds (e.g., "15", "14", "13"...) and triggers the action when it reaches zero.

## Viewer UI Controls

The story viewer displays navigation controls in the **upper-right corner**:

| Control | Always Visible | Description |
|---------|----------------|-------------|
| Exit button | Yes | Exits the story and returns to Stories browser |
| Back button | Conditional | Goes to previous scene (if `allowBackNavigation` enabled) |

### Back Navigation

Back navigation can be controlled at two levels:

1. **Global setting** in `content/main.json`:
   ```json
   { "settings": { "allowBackNavigation": true } }
   ```

2. **Per-scene override** in scene definition:
   ```json
   { "allowBack": false }
   ```

The per-scene `allowBack` overrides the global setting. This allows authors to create linear stories where users cannot go back, or to block return to specific scenes.

## Asset References

Assets are referenced using the `asset://` URI scheme:

```
asset://media/sha1hash.jpg     → assets/media/sha1hash.jpg
asset://media/sha1hash.mp3     → assets/media/sha1hash.mp3
asset://logo.png               → assets/logo.png
asset://thumbnails/preview.png → assets/thumbnails/preview.png
```

## Story Studio (Editor)

The Story Studio is the editing interface for creating and modifying stories. It opens when pressing "Edit" on any story.

### Studio Features

1. **Scene Timeline**
   - Visual list of all scenes in order
   - Drag to reorder scenes
   - Add/delete scenes
   - Duplicate scenes
   - Visual timing bar showing when elements appear

2. **Scene Editor**
   - Background selection (image picker or color picker)
   - Background appearance delay slider (0-5 seconds)
   - Element placement using anchor points (9-point grid)
   - Visual guides showing anchor positions
   - Preview mode to test timing sequence on different screen sizes

3. **Element Properties Panel**
   - Anchor point selector (visual 9-point grid)
   - Offset sliders (X and Y)
   - Size selector (small/medium/large/full)
   - Appearance timing slider (0-5 seconds)
   - Type-specific properties (text content, button shape, etc.)

4. **Timing Editor**
   - Visual timeline showing all elements
   - Drag elements on timeline to adjust `appearAt`
   - Group elements to appear together
   - Preview button to test the full sequence

5. **Trigger Configuration**
   - Link buttons to scenes (visual scene picker)
   - Configure auto-advance timer (1-60 seconds)
   - Set URL triggers
   - Set sound triggers

6. **Scene Settings**
   - Enable/disable back navigation for scene
   - Scene title (optional)
   - Background placeholder color

### Invisible Button Editing

In Studio mode, invisible buttons are displayed with a **red dotted border** so authors can see and select them. In viewer mode, they are completely invisible.

### Responsive Preview

The Studio includes a preview panel that simulates different screen sizes:
- Phone portrait (9:16)
- Phone landscape (16:9)
- Tablet portrait (3:4)
- Tablet landscape (4:3)

This helps authors verify that anchor-based positioning looks correct on all devices.

### Element Timing Preview

The Studio provides a "Play" button that simulates the scene:
1. Placeholder color shown (if background is delayed)
2. Background fades in at its `appearAt` time
3. Elements fade in at their configured `appearAt` times
4. Auto-advance countdown starts (if configured)

## File Locations

### Source Code

```
lib/stories/
├── stories.dart                 # Public exports
├── models/
│   ├── story_content.dart       # StoryContent, StoryScene, etc.
│   └── stories.dart             # Export barrel
├── pages/
│   ├── stories_home_page.dart   # Story browser
│   ├── story_viewer_page.dart   # Play stories
│   ├── story_studio_page.dart   # Create/edit stories
│   └── stories_pages.dart       # Export barrel
└── services/
    ├── stories_storage_service.dart  # NDF file management
    ├── story_ndf_service.dart        # NDF read/write
    └── stories_services.dart         # Export barrel
```

### Translation Files

```
languages/en_US/stories.json
languages/pt_PT/stories.json
```

## Implementation Status

### Phase 1: Core Structure (MVP)
- [ ] Create `lib/stories/` folder structure
- [ ] Add app registration (constants, theme, routing)
- [ ] Create StoriesHomePage with story list
- [ ] Create story viewer page
- [ ] Add translation files (en_US, pt_PT)
- [ ] Create this documentation

### Phase 2: Story Viewer
- [ ] Scene rendering with backgrounds
- [ ] Element rendering (images, text, buttons)
- [ ] Touch trigger handling
- [ ] Scene navigation
- [ ] Auto-advance with countdown

### Phase 3: Story Studio (Editor)
- [ ] Scene list management
- [ ] Background selection (image/color)
- [ ] Element placement with drag/resize
- [ ] Button shape selection
- [ ] Trigger configuration
- [ ] Media import with SHA1 deduplication

### Phase 4: Advanced Features
- [ ] Transitions between scenes
- [ ] Sound playback
- [ ] Swipe navigation
- [ ] Story templates

## Dependencies

Existing packages used:
- `archive` - ZIP handling for NDF files
- `crypto` - SHA1 hashing for media filenames
- NOSTR utilities from `lib/util/nostr_crypto.dart`

Reusing from Work app:
- `ElementPosition` concept from presentation editor
- NDF archive structure patterns
- NDF service utilities

## Theme Colors

Stories app uses purple/violet tones:
- Primary: #7B1FA2 (deep purple)
- Accent: #E1BEE7 (light purple)
- Icon: book or play icon

## Verification Checklist

### File Naming
1. Create a new story named "Test Story"
2. Verify file is created as `test-story.ndf`
3. Rename story to "My Adventure: Part 1" and verify file becomes `my-adventure-part-1.ndf`

### Scene & Background
4. Add a scene with background image
5. Set background `appearAt: 2000` (2 second delay) with placeholder color
6. Verify placeholder shows first, then background fades in
7. Verify image is stored with SHA1 filename in `assets/media/`

### Element Positioning
8. Add text element anchored to `topCenter`
9. Add button anchored to `bottomCenter` with offset
10. Preview on different screen sizes (phone, tablet) and verify elements adapt
11. Verify safe zones keep elements away from screen edges

### Element Timing
12. Set text `appearAt: 1000` and button `appearAt: 3000`
13. Use Studio timeline to visualize element appearance order
14. Test timing sequence in preview mode

### Buttons & Triggers
15. Add invisible button and verify it shows red dotted border in Studio
16. Link button to second scene with goToScene trigger
17. Test navigation between scenes

### Auto-Advance
18. Add second scene with auto-advance timer (15 seconds)
19. Verify countdown displays in lower-right corner
20. Verify action triggers when countdown reaches zero

### Navigation Controls
21. Test back button in upper-right corner
22. Disable `allowBack` on a scene and verify back button is hidden
23. Verify exit button always works

### NDF Structure
24. Extract `.ndf` file and verify correct ZIP structure
25. Verify `ndf.json` and `permissions.json` at root
26. Verify `content/main.json` and `content/scenes/` contain story data
27. Verify anchor-based positions in scene JSON (no x/y pixel values)

### Localization
28. Switch language to pt_PT and verify translations
