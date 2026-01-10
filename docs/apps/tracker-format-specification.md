# Tracker Format Specification

Version: 1.0.0
Last Updated: 2026-01-07

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [File Organization](#file-organization)
4. [Collection Metadata](#collection-metadata)
5. [Settings](#settings)
6. [Paths Tracking](#paths-tracking)
7. [Measurements Tracking](#measurements-tracking)
8. [Exercise Tracking](#exercise-tracking)
9. [Fitness Plans](#fitness-plans)
10. [Location Sharing](#location-sharing)
11. [Unified Proximity Tracking](#unified-proximity-tracking)
12. [Privacy & Security](#privacy--security)
14. [Battery Optimization](#battery-optimization)
15. [NOSTR Integration](#nostr-integration)
16. [Validation Rules](#validation-rules)
17. [Parsing Implementation](#parsing-implementation)
18. [Best Practices](#best-practices)
19. [Related Documentation](#related-documentation)
20. [Change Log](#change-log)

---

## Overview

The Tracker app enables comprehensive personal tracking capabilities within Geogram:

- **Paths** - GPS path recording with configurable intervals for battery efficiency
- **Measurements** - Manual data entry (weight, blood pressure, etc.) with timestamps for trend visualization
- **Exercises** - Simple logging of exercise counts (e.g., "20 pushups today")
- **Plans** - Weekly fitness plans with combined goals and progress tracking
- **Location Sharing** - Share location with groups or temporarily with individuals
- **Proximity** - Unified tracking of nearby Bluetooth devices and places within 50m

All data is stored locally in JSON format, with optional NOSTR signatures for verification.

---

## Design Principles

### Core Principles

1. **Privacy-First** - All data is private by default; sharing requires explicit action
2. **Offline-First** - Full functionality without network connectivity
3. **Battery-Conscious** - Configurable intervals for GPS and Bluetooth to preserve battery
4. **Metric-Oriented** - Data structured for easy chart generation and analytics
5. **Text-Based Storage** - JSON format for human readability and easy debugging
6. **NOSTR Integration** - Optional cryptographic signatures for data verification

### Data Ownership

- Users own their data completely
- No server-side storage required
- Export capabilities for data portability
- Selective sharing with cryptographic proof of origin

---

## File Organization

The collection folder is `{collection_id}/` (e.g., `my_health_tracker/`). All contents are directly inside:

```
{collection_id}/
├── metadata.json                    # Collection metadata
├── settings.json                    # Tracker settings
├── extra/
│   └── security.json                # Permissions
├── paths/                           # GPS path recordings
│   └── {YYYY}/
│       └── path_{YYYYMMDD}_{id}/
│           ├── path.json            # Path metadata
│           └── points.json          # GPS points array
├── measurements/                    # Manual measurements
│   └── {YYYY}/
│       ├── weight.json              # Weight readings for year
│       ├── blood_pressure.json      # Blood pressure readings
│       ├── heart_rate.json          # Heart rate readings
│       └── custom.json              # Custom measurements
├── exercises/                       # Exercise tracking
│   └── {YYYY}/
│       ├── pushups.json             # Push-up entries for year
│       ├── abdominals.json          # Abdominal entries
│       ├── running.json             # Running entries
│       └── custom.json              # Custom exercise entries
├── plans/                           # Fitness plans with goals
│   ├── active/                      # Currently active plans
│   │   └── plan_{id}.json
│   └── archived/                    # Completed/expired plans
│       └── plan_{id}.json
├── sharing/                         # Location sharing (outbound)
│   ├── groups/                      # Group-based shares
│   │   └── share_{group_id}.json
│   └── temporary/                   # Time-limited shares
│       └── share_{YYYYMMDD}_{id}.json
├── locations/                       # Received locations (inbound)
│   └── {callsign}_location.json
├── proximity/                       # Bluetooth proximity data
│   └── {YYYY}/
│       └── proximity_{YYYYMMDD}.json
└── visits/                          # Check-in/checkout tracking
    ├── {YYYY}/
    │   └── visits_{YYYYMMDD}.json   # Daily visit records
    └── stats.json                   # Aggregated place statistics
```

### Naming Conventions

- **Date format in filenames**: `YYYYMMDD` (e.g., `20260115`)
- **ID format**: Alphanumeric, 6-12 characters (e.g., `abc123`, `xyz789def`)
- **Timestamp format in JSON**: ISO 8601 with timezone (e.g., `2026-01-15T07:00:00Z`)
- **Coordinates**: Decimal degrees (e.g., `38.7223`, `-9.1393`)

---

## Collection Metadata

### metadata.json

```json
{
  "id": "tracker_abc123",
  "type": "tracker",
  "version": "1.0.0",
  "title": "My Health Tracker",
  "description": "Personal health and activity tracking",
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-15T12:00:00Z",
  "owner_callsign": "X1ABCD",
  "features": {
    "paths": true,
    "measurements": true,
    "exercises": true,
    "sharing": true,
    "proximity": true,
    "visits": true
  },
  "metadata": {
    "npub": "npub1...",
    "signature": "sig..."
  }
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique collection identifier |
| `type` | string | Yes | Must be `"tracker"` |
| `version` | string | Yes | Specification version |
| `title` | string | Yes | Human-readable title |
| `description` | string | No | Collection description |
| `created_at` | string | Yes | ISO 8601 creation timestamp |
| `updated_at` | string | Yes | ISO 8601 last update timestamp |
| `owner_callsign` | string | Yes | Owner's Geogram callsign |
| `features` | object | No | Enabled/disabled features |
| `metadata` | object | No | NOSTR verification data |

---

## Settings

### settings.json

```json
{
  "paths": {
    "default_interval_seconds": 60,
    "auto_pause_when_stationary": true,
    "stationary_threshold_meters": 5,
    "max_accuracy_meters": 50
  },
  "measurements": {
    "preferred_units": {
      "weight": "kg",
      "height": "cm",
      "temperature": "celsius"
    },
    "reminders": {
      "weight": {
        "enabled": true,
        "time": "07:00",
        "days": ["monday", "wednesday", "friday"]
      }
    }
  },
  "exercises": {
    "auto_link_paths_to_cardio": true
  },
  "sharing": {
    "default_update_interval_seconds": 300,
    "default_accuracy": "approximate",
    "auto_disable_after_hours": 24
  },
  "proximity": {
    "scan_interval_seconds": 30,
    "min_detection_seconds": 60,
    "enabled": true
  },
  "visits": {
    "detection_radius_meters": 20,
    "min_stay_seconds": 120,
    "background_interval_seconds": 300,
    "battery_saver_mode": true,
    "enabled": true
  }
}
```

### Settings Sections

#### paths
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `default_interval_seconds` | int | 60 | GPS reading interval |
| `auto_pause_when_stationary` | bool | true | Pause recording when not moving |
| `stationary_threshold_meters` | int | 5 | Movement threshold for stationary detection |
| `max_accuracy_meters` | int | 50 | Discard readings with worse accuracy |

#### measurements
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `preferred_units` | object | - | Unit preferences per measurement type |
| `reminders` | object | - | Reminder configuration per type |

#### exercises
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `auto_link_paths_to_cardio` | bool | true | Automatically link GPS paths to cardio exercises |

#### sharing
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `default_update_interval_seconds` | int | 300 | Location update frequency |
| `default_accuracy` | string | approximate | Default share accuracy level |
| `auto_disable_after_hours` | int | 24 | Auto-disable temporary shares after this time |

#### proximity
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `scan_interval_seconds` | int | 30 | Bluetooth scan interval |
| `min_detection_seconds` | int | 60 | Minimum time to register proximity |
| `enabled` | bool | true | Enable/disable proximity tracking |

#### visits
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `detection_radius_meters` | int | 20 | Distance threshold for check-in |
| `min_stay_seconds` | int | 120 | Minimum time to register a visit |
| `background_interval_seconds` | int | 300 | GPS check interval in background |
| `battery_saver_mode` | bool | true | Reduce frequency when battery is low |
| `enabled` | bool | true | Enable/disable visit tracking |

---

## Paths Tracking

### Purpose

Record GPS paths with configurable intervals for activities like running, cycling, hiking, or general travel tracking.

### path.json Format

```json
{
  "id": "path_20260115_abc123",
  "title": "Morning Run",
  "description": "Run around the park",
  "started_at": "2026-01-15T07:00:00Z",
  "ended_at": "2026-01-15T07:45:00Z",
  "status": "completed",
  "interval_seconds": 60,
  "total_points": 45,
  "total_distance_meters": 5230,
  "elevation_gain_meters": 45,
  "elevation_loss_meters": 42,
  "avg_speed_mps": 1.94,
  "max_speed_mps": 3.2,
  "bounds": {
    "min_lat": 38.7200,
    "max_lat": 38.7250,
    "min_lon": -9.1420,
    "max_lon": -9.1380
  },
  "tags": ["running", "morning"],
  "owner_callsign": "X1ABCD",
  "metadata": {
    "npub": "npub1...",
    "signature": "sig..."
  }
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique path identifier |
| `title` | string | No | Human-readable title |
| `description` | string | No | Path description |
| `started_at` | string | Yes | ISO 8601 start timestamp |
| `ended_at` | string | No | ISO 8601 end timestamp (null if in progress) |
| `status` | string | Yes | `recording`, `paused`, `completed`, `cancelled` |
| `interval_seconds` | int | Yes | GPS reading interval used |
| `total_points` | int | Yes | Number of GPS points recorded |
| `total_distance_meters` | float | Yes | Total distance calculated |
| `elevation_gain_meters` | float | No | Total elevation gain |
| `elevation_loss_meters` | float | No | Total elevation loss |
| `avg_speed_mps` | float | No | Average speed in meters/second |
| `max_speed_mps` | float | No | Maximum speed recorded |
| `bounds` | object | No | Bounding box of the path |
| `tags` | array | No | User-defined tags |
| `owner_callsign` | string | Yes | Owner's callsign |
| `metadata` | object | No | NOSTR verification |

### points.json Format

```json
{
  "path_id": "path_20260115_abc123",
  "points": [
    {
      "index": 0,
      "timestamp": "2026-01-15T07:00:00Z",
      "lat": 38.7223,
      "lon": -9.1393,
      "altitude": 25.5,
      "accuracy": 5.2,
      "speed": 0.0,
      "bearing": null
    },
    {
      "index": 1,
      "timestamp": "2026-01-15T07:01:00Z",
      "lat": 38.7225,
      "lon": -9.1390,
      "altitude": 26.0,
      "accuracy": 4.8,
      "speed": 2.5,
      "bearing": 45.2
    }
  ]
}
```

### Point Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `index` | int | Yes | Sequential point index |
| `timestamp` | string | Yes | ISO 8601 timestamp |
| `lat` | float | Yes | Latitude in decimal degrees |
| `lon` | float | Yes | Longitude in decimal degrees |
| `altitude` | float | No | Altitude in meters |
| `accuracy` | float | No | GPS accuracy in meters |
| `speed` | float | No | Speed in meters/second |
| `bearing` | float | No | Bearing/heading in degrees (0-360) |

### Distance Calculation

Use the Haversine formula for calculating distances between points:

```dart
double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000; // Earth radius in meters
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}
```

### Path Status Flow

```
recording -> paused -> recording -> completed
    |                      |
    v                      v
cancelled              cancelled
```

---

## Measurements Tracking

### Purpose

Track manual measurements like weight, blood pressure, glucose, etc. with timestamps for trend visualization and health monitoring.

### Built-in Measurement Types

| Type ID | Display Name | Unit | Min | Max | Decimal Places |
|---------|--------------|------|-----|-----|----------------|
| `weight` | Weight | kg | 0 | 500 | 1 |
| `height` | Height | cm | 0 | 300 | 1 |
| `blood_pressure_systolic` | Systolic BP | mmHg | 0 | 300 | 0 |
| `blood_pressure_diastolic` | Diastolic BP | mmHg | 0 | 200 | 0 |
| `heart_rate` | Heart Rate | bpm | 0 | 300 | 0 |
| `blood_glucose` | Blood Glucose | mg/dL | 0 | 600 | 0 |
| `body_fat` | Body Fat | % | 0 | 100 | 1 |
| `body_temperature` | Temperature | °C | 30 | 45 | 1 |
| `body_water` | Body Water | % | 0 | 100 | 1 |
| `muscle_mass` | Muscle Mass | kg | 0 | 200 | 1 |

### Measurement File Format (e.g., measurements/2026/weight.json)

Files are organized by year: `measurements/{YYYY}/weight.json`

```json
{
  "type_id": "weight",
  "year": 2026,
  "display_name": "Weight",
  "unit": "kg",
  "min_value": 0,
  "max_value": 500,
  "decimal_places": 1,
  "goal": {
    "target_value": 70.0,
    "target_date": "2026-06-01",
    "direction": "decrease"
  },
  "entries": [
    {
      "id": "m_20260115_001",
      "timestamp": "2026-01-15T07:30:00Z",
      "value": 75.5,
      "notes": "Before breakfast",
      "tags": ["morning", "fasting"],
      "metadata": {
        "npub": "npub1...",
        "signature": "sig..."
      }
    },
    {
      "id": "m_20260116_001",
      "timestamp": "2026-01-16T07:32:00Z",
      "value": 75.2,
      "notes": "",
      "tags": ["morning"]
    }
  ],
  "statistics": {
    "count": 2,
    "min": 75.2,
    "max": 75.5,
    "avg": 75.35,
    "first_entry": "2026-01-15T07:30:00Z",
    "last_entry": "2026-01-16T07:32:00Z"
  }
}
```

### Blood Pressure Format (measurements/2026/blood_pressure.json)

Blood pressure requires two values (systolic and diastolic):

```json
{
  "type_id": "blood_pressure",
  "year": 2026,
  "display_name": "Blood Pressure",
  "entries": [
    {
      "id": "bp_20260115_001",
      "timestamp": "2026-01-15T07:30:00Z",
      "systolic": 120,
      "diastolic": 80,
      "heart_rate": 72,
      "arm": "left",
      "position": "sitting",
      "notes": "Morning reading",
      "tags": ["morning"]
    }
  ]
}
```

### Custom Measurements (measurements/2026/custom.json)

```json
{
  "type_id": "custom",
  "year": 2026,
  "custom_types": [
    {
      "id": "sleep_hours",
      "display_name": "Sleep Hours",
      "unit": "hours",
      "min_value": 0,
      "max_value": 24,
      "decimal_places": 1
    },
    {
      "id": "water_intake",
      "display_name": "Water Intake",
      "unit": "ml",
      "min_value": 0,
      "max_value": 10000,
      "decimal_places": 0
    }
  ],
  "entries": [
    {
      "id": "c_20260115_001",
      "custom_type_id": "sleep_hours",
      "timestamp": "2026-01-15T07:00:00Z",
      "value": 7.5,
      "notes": ""
    }
  ]
}
```

### Entry Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique entry identifier |
| `timestamp` | string | Yes | ISO 8601 measurement time |
| `value` | float | Yes | Measured value |
| `notes` | string | No | User notes |
| `tags` | array | No | User-defined tags |
| `metadata` | object | No | NOSTR verification |

---

## Exercise Tracking

### Purpose

Track individual exercise entries like "20 pushups today" or "10 abdominals today". Simple daily logging of exercise counts for trend visualization.

### Built-in Exercise Types

| Type ID | Display Name | Unit | Category |
|---------|--------------|------|----------|
| `pushups` | Push-ups | reps | strength |
| `abdominals` | Abdominals | reps | strength |
| `squats` | Squats | reps | strength |
| `pullups` | Pull-ups | reps | strength |
| `lunges` | Lunges | reps | strength |
| `planks` | Planks | seconds | strength |
| `running` | Running | meters | cardio |
| `walking` | Walking | meters | cardio |
| `cycling` | Cycling | meters | cardio |
| `swimming` | Swimming | meters | cardio |

### Exercise File Format (e.g., exercises/2026/pushups.json)

Files are organized by year: `exercises/{YYYY}/pushups.json`

```json
{
  "exercise_id": "pushups",
  "year": 2026,
  "display_name": "Push-ups",
  "unit": "reps",
  "category": "strength",
  "goal": {
    "daily_target": 50,
    "weekly_target": 300
  },
  "entries": [
    {
      "id": "e_20260115_001",
      "timestamp": "2026-01-15T07:30:00Z",
      "count": 20,
      "notes": "Morning routine",
      "tags": ["morning"],
      "metadata": {
        "npub": "npub1...",
        "signature": "sig..."
      }
    },
    {
      "id": "e_20260115_002",
      "timestamp": "2026-01-15T18:00:00Z",
      "count": 15,
      "notes": "Evening set",
      "tags": ["evening"]
    }
  ],
  "statistics": {
    "total_count": 35,
    "total_entries": 2,
    "first_entry": "2026-01-15T07:30:00Z",
    "last_entry": "2026-01-15T18:00:00Z"
  }
}
```

### Cardio Exercise Format (e.g., exercises/2026/running.json)

For cardio exercises, optionally link to a GPS path:

```json
{
  "exercise_id": "running",
  "year": 2026,
  "display_name": "Running",
  "unit": "meters",
  "category": "cardio",
  "goal": {
    "weekly_target": 20000
  },
  "entries": [
    {
      "id": "e_20260115_run001",
      "timestamp": "2026-01-15T07:00:00Z",
      "count": 5230,
      "duration_seconds": 2700,
      "path_id": "path_20260115_abc123",
      "notes": "Morning run in the park",
      "tags": ["morning", "outdoor"]
    }
  ]
}
```

### Custom Exercises (exercises/2026/custom.json)

```json
{
  "year": 2026,
  "custom_types": [
    {
      "id": "burpees",
      "display_name": "Burpees",
      "unit": "reps",
      "category": "cardio"
    },
    {
      "id": "jumping_jacks",
      "display_name": "Jumping Jacks",
      "unit": "reps",
      "category": "cardio"
    }
  ],
  "entries": [
    {
      "id": "c_20260115_001",
      "exercise_id": "burpees",
      "timestamp": "2026-01-15T08:00:00Z",
      "count": 30,
      "notes": ""
    }
  ]
}
```

### Entry Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique entry identifier |
| `timestamp` | string | Yes | ISO 8601 time of exercise |
| `count` | int/float | Yes | Number of reps, meters, or seconds |
| `duration_seconds` | int | No | Duration for cardio exercises |
| `path_id` | string | No | Link to GPS path (cardio only) |
| `notes` | string | No | User notes |
| `tags` | array | No | User tags |
| `metadata` | object | No | NOSTR verification |

### Daily Aggregation

The app can compute daily totals from entries:

```json
{
  "date": "2026-01-15",
  "exercises": {
    "pushups": {
      "total": 35,
      "entries": 2,
      "goal_progress": 0.70
    },
    "abdominals": {
      "total": 50,
      "entries": 1,
      "goal_progress": 1.0
    }
  }
}
```

---

## Fitness Plans

### Purpose

Define weekly fitness plans with combined exercise goals. Track progress against these goals over time and stay motivated with clear targets.

### How Plans Work

1. Create a plan with one or more exercise goals
2. Goals can be daily-based (converted to weekly) or weekly-based
3. Set a start and end date for the plan
4. Track progress automatically from exercise entries
5. Archive plans when completed or expired

### Plan File Format (plans/active/plan_{id}.json)

```json
{
  "id": "plan_fitness_2026",
  "title": "2026 Fitness Plan",
  "description": "Stay fit with daily exercises and weekly cardio",
  "status": "active",
  "created_at": "2026-01-01T00:00:00Z",
  "starts_at": "2026-01-01",
  "ends_at": "2026-12-31",
  "goals": [
    {
      "id": "goal_abs",
      "exercise_id": "abdominals",
      "description": "20 abdominals per day",
      "target_type": "daily",
      "daily_target": 20,
      "weekly_target": 140
    },
    {
      "id": "goal_pushups",
      "exercise_id": "pushups",
      "description": "30 pushups per day",
      "target_type": "daily",
      "daily_target": 30,
      "weekly_target": 210
    },
    {
      "id": "goal_running",
      "exercise_id": "running",
      "description": "16 km per week",
      "target_type": "weekly",
      "daily_target": null,
      "weekly_target": 16000
    }
  ],
  "reminders": {
    "enabled": true,
    "time": "07:00",
    "days": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
  },
  "owner_callsign": "X1ABCD",
  "metadata": {
    "npub": "npub1...",
    "signature": "sig..."
  }
}
```

### Goal Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique goal identifier |
| `exercise_id` | string | Yes | Reference to exercise type |
| `description` | string | Yes | Human-readable goal description |
| `target_type` | string | Yes | `daily` or `weekly` |
| `daily_target` | int | No | Daily target (null for weekly-only) |
| `weekly_target` | int | Yes | Weekly target (sum of daily or direct) |

### Plan Status Values

| Status | Description |
|--------|-------------|
| `active` | Plan is currently running |
| `paused` | Plan temporarily paused |
| `completed` | Plan ended successfully |
| `expired` | Plan passed end date |
| `cancelled` | Plan cancelled by user |

### Weekly Progress (Computed)

Progress is computed from exercise entries, not stored. Example structure:

```json
{
  "plan_id": "plan_fitness_2026",
  "week": "2026-W02",
  "week_start": "2026-01-06",
  "week_end": "2026-01-12",
  "goals": [
    {
      "goal_id": "goal_abs",
      "exercise_id": "abdominals",
      "weekly_target": 140,
      "weekly_actual": 120,
      "progress_percent": 85.7,
      "daily_breakdown": {
        "2026-01-06": 20,
        "2026-01-07": 20,
        "2026-01-08": 15,
        "2026-01-09": 20,
        "2026-01-10": 25,
        "2026-01-11": 20,
        "2026-01-12": 0
      },
      "status": "behind"
    },
    {
      "goal_id": "goal_pushups",
      "exercise_id": "pushups",
      "weekly_target": 210,
      "weekly_actual": 220,
      "progress_percent": 104.8,
      "status": "achieved"
    },
    {
      "goal_id": "goal_running",
      "exercise_id": "running",
      "weekly_target": 16000,
      "weekly_actual": 18500,
      "progress_percent": 115.6,
      "status": "achieved"
    }
  ],
  "overall_progress_percent": 101.7,
  "goals_achieved": 2,
  "goals_total": 3
}
```

### Progress Status Values

| Status | Condition |
|--------|-----------|
| `achieved` | >= 100% of target |
| `on_track` | >= 70% with days remaining |
| `behind` | < 70% or missed after week ends |
| `not_started` | 0% progress |

### Plan History (Archived)

When a plan is completed or expired, it moves to `plans/archived/` with summary statistics:

```json
{
  "id": "plan_fitness_2026",
  "title": "2026 Fitness Plan",
  "status": "completed",
  "starts_at": "2026-01-01",
  "ends_at": "2026-12-31",
  "archived_at": "2027-01-01T00:00:00Z",
  "summary": {
    "total_weeks": 52,
    "weeks_all_goals_achieved": 38,
    "weeks_partial": 10,
    "weeks_missed": 4,
    "achievement_rate_percent": 73.1,
    "goals_summary": [
      {
        "goal_id": "goal_abs",
        "exercise_id": "abdominals",
        "total_target": 7280,
        "total_actual": 6850,
        "achievement_percent": 94.1
      },
      {
        "goal_id": "goal_pushups",
        "exercise_id": "pushups",
        "total_target": 10920,
        "total_actual": 11200,
        "achievement_percent": 102.6
      },
      {
        "goal_id": "goal_running",
        "exercise_id": "running",
        "total_target": 832000,
        "total_actual": 780000,
        "achievement_percent": 93.8
      }
    ]
  }
}
```

### Multiple Active Plans

Users can have multiple active plans simultaneously:

```
plans/
├── active/
│   ├── plan_morning_routine.json    # Daily morning exercises
│   ├── plan_cardio_2026.json        # Weekly cardio goals
│   └── plan_strength_q1.json        # Q1 strength training
└── archived/
    └── plan_december_challenge.json
```

### Plan Templates (Optional)

Common plan templates can be stored for quick setup:

```json
{
  "id": "template_beginner_fitness",
  "title": "Beginner Fitness (Template)",
  "is_template": true,
  "goals": [
    {
      "exercise_id": "pushups",
      "target_type": "daily",
      "daily_target": 10,
      "weekly_target": 70
    },
    {
      "exercise_id": "abdominals",
      "target_type": "daily",
      "daily_target": 15,
      "weekly_target": 105
    },
    {
      "exercise_id": "walking",
      "target_type": "weekly",
      "weekly_target": 10000
    }
  ]
}
```

---

## Location Sharing

### Purpose

Share your location with groups (family, friends) or temporarily with individuals. Control accuracy levels and update intervals.

### Share Accuracy Levels

| Level | Description | Radius | Use Case |
|-------|-------------|--------|----------|
| `precise` | Exact location | ~10m | Meeting up, emergencies |
| `approximate` | Fuzzy location | ~500m | Family safety check |
| `city` | City level only | City bounds | Social presence |

### Group Share Format (sharing/groups/share_{group_id}.json)

```json
{
  "id": "share_family",
  "type": "group",
  "group_id": "group_family",
  "group_name": "Family",
  "active": true,
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-15T12:00:00Z",
  "update_interval_seconds": 300,
  "share_accuracy": "approximate",
  "members": [
    {
      "callsign": "ALICE1",
      "npub": "npub1alice...",
      "added_at": "2026-01-01T00:00:00Z"
    },
    {
      "callsign": "BOB42",
      "npub": "npub1bob...",
      "added_at": "2026-01-01T00:00:00Z"
    }
  ],
  "schedule": {
    "always_on": true
  },
  "last_broadcast": "2026-01-15T14:30:00Z",
  "owner_callsign": "X1ABCD",
  "metadata": {
    "npub": "npub1...",
    "signature": "sig..."
  }
}
```

### Scheduled Share

```json
{
  "schedule": {
    "always_on": false,
    "time_ranges": [
      {
        "days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
        "start_time": "08:00",
        "end_time": "18:00"
      }
    ]
  }
}
```

### Temporary Share Format (sharing/temporary/share_{YYYYMMDD}_{id}.json)

```json
{
  "id": "share_20260115_temp001",
  "type": "temporary",
  "recipients": [
    {
      "callsign": "Y2EFGH",
      "npub": "npub1..."
    }
  ],
  "active": true,
  "created_at": "2026-01-15T14:00:00Z",
  "expires_at": "2026-01-15T17:00:00Z",
  "duration_minutes": 180,
  "reason": "Meeting at the park",
  "update_interval_seconds": 60,
  "share_accuracy": "precise",
  "last_broadcast": "2026-01-15T14:30:00Z",
  "owner_callsign": "X1ABCD",
  "metadata": {
    "npub": "npub1...",
    "signature": "sig..."
  }
}
```

### Received Location Format (locations/{callsign}_location.json)

```json
{
  "callsign": "ALICE1",
  "display_name": "Alice",
  "npub": "npub1alice...",
  "last_update": "2026-01-15T14:30:00Z",
  "location": {
    "lat": 38.7223,
    "lon": -9.1393,
    "accuracy_level": "approximate",
    "accuracy_meters": 500
  },
  "share_info": {
    "type": "group",
    "share_id": "share_family",
    "share_name": "Family"
  },
  "expires_at": null,
  "history": [
    {
      "timestamp": "2026-01-15T14:00:00Z",
      "lat": 38.7200,
      "lon": -9.1400
    },
    {
      "timestamp": "2026-01-15T14:30:00Z",
      "lat": 38.7223,
      "lon": -9.1393
    }
  ],
  "history_max_entries": 10
}
```

### Share Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique share identifier |
| `type` | string | Yes | `group` or `temporary` |
| `active` | bool | Yes | Share is currently active |
| `update_interval_seconds` | int | Yes | How often to broadcast |
| `share_accuracy` | string | Yes | Accuracy level |
| `expires_at` | string | No | Expiration time (temporary only) |
| `members` / `recipients` | array | Yes | Who receives the share |
| `owner_callsign` | string | Yes | Owner's callsign |

---

## Unified Proximity Tracking

### Purpose

Track the amount of time spent near:
1. **Devices**: Other Geogram users within Bluetooth range
2. **Places**: Registered places within 50 meters (from internal, station, or connect sources)

### How It Works

1. Subscribe to `PositionUpdatedEvent` from LocationProviderService (EventBus)
2. On each GPS update, scan for nearby Bluetooth devices
3. Check current location against registered places (50m radius)
4. Record proximity entries with timestamps and location
5. Store in weekly folders with individual track files per device/place

### Storage Structure

```
proximity/
└── {YYYY}/
    └── W{WW}/                          # Week folder (W01-W52)
        ├── X1ABCD-track.json           # Device track by callsign
        ├── ALICE1-track.json           # Another device
        ├── place_home_38_72_n9_14-track.json   # Place track
        └── place_office_38_73_n9_15-track.json
```

### Track File Format (proximity/{YYYY}/W{WW}/{id}-track.json)

**Device track:**
```json
{
  "id": "X1ABCD",
  "type": "device",
  "display_name": "Alice",
  "callsign": "X1ABCD",
  "npub": "npub1alice...",
  "entries": [
    {
      "timestamp": "2026-01-15T09:00:00Z",
      "lat": 38.7223,
      "lon": -9.1393,
      "ended_at": "2026-01-15T12:30:00Z",
      "duration_seconds": 12600
    }
  ],
  "week_summary": {
    "total_seconds": 23400,
    "total_entries": 2,
    "first_detection": "2026-01-15T09:00:00Z",
    "last_detection": "2026-01-15T17:00:00Z"
  }
}
```

**Place track:**
```json
{
  "id": "place_home_38_72_n9_14",
  "type": "place",
  "display_name": "Home",
  "source": "internal",
  "place_id": "places_collection_abc/place_xyz",
  "coordinates": {"lat": 38.7223, "lon": -9.1393},
  "entries": [...],
  "week_summary": {...}
}
```

### Entry Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | string | Yes | ISO 8601 start time |
| `lat` | double | Yes | Latitude when detected |
| `lon` | double | Yes | Longitude when detected |
| `ended_at` | string | No | ISO 8601 end time (open if null) |
| `duration_seconds` | int | No | Duration in seconds |

### Week Summary Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `total_seconds` | int | Yes | Total time this week |
| `total_entries` | int | Yes | Number of detection sessions |
| `first_detection` | string | No | ISO 8601 first detection |
| `last_detection` | string | No | ISO 8601 last detection |

### Detection Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Place radius | 50m | Maximum distance to detect a place |
| Session timeout | 2 min | Gap before starting new entry |
| Places cache | 5 min | How often to refresh places list |

### Legacy Format

> **Note:** Previous versions stored daily proximity and visits separately:
> - `proximity/{YYYY}/proximity_{YYYYMMDD}.json` - Bluetooth contacts
> - `visits/{YYYY}/visits_{YYYYMMDD}.json` - Place check-ins
>
> These files are preserved for backward compatibility but new data uses the unified weekly format.

---

## Legacy: Daily Proximity Log (proximity/{YYYY}/proximity_{YYYYMMDD}.json)

```json
{
  "date": "2026-01-15",
  "owner_callsign": "X1ABCD",
  "sessions": [
    {
      "contact_callsign": "ALICE1",
      "contact_npub": "npub1alice...",
      "contact_name": "Alice",
      "periods": [
        {
          "started_at": "2026-01-15T09:00:00Z",
          "ended_at": "2026-01-15T12:30:00Z",
          "duration_seconds": 12600
        },
        {
          "started_at": "2026-01-15T14:00:00Z",
          "ended_at": "2026-01-15T17:00:00Z",
          "duration_seconds": 10800
        }
      ],
      "total_seconds": 23400,
      "total_periods": 2
    },
    {
      "contact_callsign": "BOB42",
      "contact_npub": "npub1bob...",
      "contact_name": "Bob",
      "periods": [
        {
          "started_at": "2026-01-15T10:00:00Z",
          "ended_at": "2026-01-15T11:00:00Z",
          "duration_seconds": 3600
        }
      ],
      "total_seconds": 3600,
      "total_periods": 1
    }
  ],
  "daily_summary": {
    "total_contacts": 2,
    "total_seconds": 27000,
    "most_time_with": "ALICE1"
  }
}
```

### Proximity Statistics (computed, not stored)

Statistics are computed on-demand from daily logs:

```json
{
  "contact_callsign": "ALICE1",
  "period": "2026-01",
  "total_seconds": 510000,
  "days_detected": 22,
  "avg_seconds_per_day": 23182,
  "longest_session_seconds": 28800,
  "first_detection": "2026-01-01T08:30:00Z",
  "last_detection": "2026-01-31T18:00:00Z"
}
```

### Period Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `started_at` | string | Yes | ISO 8601 start time |
| `ended_at` | string | Yes | ISO 8601 end time |
| `duration_seconds` | int | Yes | Duration in seconds |

---

## Place Visits

### Purpose

Automatically detect when you enter or exit registered places (from your Places collection) and track time spent at each location.

### How It Works

1. Background GPS monitoring at configured intervals
2. Check current location against registered places
3. When within detection radius (default 20m), start counting
4. Record check-in/checkout times and duration
5. Aggregate statistics for each place

### Daily Visits Log (visits/{YYYY}/visits_{YYYYMMDD}.json)

```json
{
  "date": "2026-01-15",
  "owner_callsign": "X1ABCD",
  "visits": [
    {
      "id": "visit_20260115_001",
      "place_id": "38.7223_-9.1393_home",
      "place_name": "Home",
      "place_category": "residence",
      "place_coordinates": {
        "lat": 38.7223,
        "lon": -9.1393
      },
      "checked_in_at": "2026-01-15T00:00:00Z",
      "checked_out_at": "2026-01-15T08:30:00Z",
      "duration_seconds": 30600,
      "auto_detected": true,
      "detection_accuracy_meters": 8.5
    },
    {
      "id": "visit_20260115_002",
      "place_id": "38.7300_-9.1400_office",
      "place_name": "Office",
      "place_category": "work",
      "place_coordinates": {
        "lat": 38.7300,
        "lon": -9.1400
      },
      "checked_in_at": "2026-01-15T09:00:00Z",
      "checked_out_at": "2026-01-15T18:00:00Z",
      "duration_seconds": 32400,
      "auto_detected": true,
      "notes": "Long day today"
    },
    {
      "id": "visit_20260115_003",
      "place_id": "38.7223_-9.1393_home",
      "place_name": "Home",
      "place_category": "residence",
      "place_coordinates": {
        "lat": 38.7223,
        "lon": -9.1393
      },
      "checked_in_at": "2026-01-15T18:30:00Z",
      "checked_out_at": null,
      "duration_seconds": null,
      "auto_detected": true,
      "status": "checked_in"
    }
  ],
  "daily_summary": {
    "total_visits": 3,
    "total_tracked_seconds": 63000,
    "places_visited": 2,
    "most_time_at": "38.7300_-9.1400_office"
  }
}
```

### Place Statistics (visits/stats.json)

```json
{
  "places": [
    {
      "place_id": "38.7223_-9.1393_home",
      "place_name": "Home",
      "place_category": "residence",
      "stats": {
        "total_visits": 365,
        "total_seconds": 15768000,
        "avg_seconds_per_visit": 43200,
        "avg_visits_per_week": 7,
        "first_visit": "2025-01-01T00:00:00Z",
        "last_visit": "2026-01-15T18:30:00Z",
        "longest_visit_seconds": 86400,
        "shortest_visit_seconds": 1800
      },
      "monthly": {
        "2026-01": {
          "visits": 15,
          "seconds": 648000,
          "avg_seconds_per_visit": 43200
        }
      },
      "weekly": {
        "2026-W02": {
          "visits": 7,
          "seconds": 302400
        }
      }
    },
    {
      "place_id": "38.7300_-9.1400_office",
      "place_name": "Office",
      "place_category": "work",
      "stats": {
        "total_visits": 220,
        "total_seconds": 7128000,
        "avg_seconds_per_visit": 32400,
        "first_visit": "2025-01-06T09:00:00Z",
        "last_visit": "2026-01-15T09:00:00Z"
      },
      "monthly": {
        "2026-01": {
          "visits": 10,
          "seconds": 324000
        }
      }
    }
  ],
  "updated_at": "2026-01-15T18:30:00Z",
  "total_places_tracked": 2,
  "tracking_since": "2025-01-01T00:00:00Z"
}
```

### Visit Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique visit identifier |
| `place_id` | string | Yes | Reference to Places collection |
| `place_name` | string | Yes | Cached place name |
| `place_category` | string | No | Place category |
| `place_coordinates` | object | Yes | Cached coordinates |
| `checked_in_at` | string | Yes | ISO 8601 arrival time |
| `checked_out_at` | string | No | ISO 8601 departure time (null if current) |
| `duration_seconds` | int | No | Visit duration (null if current) |
| `auto_detected` | bool | Yes | Auto vs manual check-in |
| `status` | string | No | `checked_in` if currently at place |
| `notes` | string | No | User notes |

---

## Privacy & Security

### Data Privacy

1. **Local Storage** - All data stored locally on device
2. **No Cloud Sync** - No automatic server uploads
3. **Selective Sharing** - Explicit user action required to share
4. **Accuracy Control** - Choose what level of detail to share
5. **Expiring Shares** - Temporary shares auto-disable

### Visibility Levels

All tracker types support four visibility levels:

| Level | Description | Access Control |
|-------|-------------|----------------|
| `private` | Only the owner can access | Default for all data |
| `public` | Anyone can view | No restrictions |
| `unlisted` | Only those with link | Requires secret `unlisted_id` |
| `restricted` | Specific contacts/groups | Explicit allow list |

### Visibility Field

Every tracker item can include a `visibility` field:

```json
{
  "visibility": {
    "level": "private"
  }
}
```

### Private Visibility (Default)

Only the owner can access. This is the default when no visibility is specified.

```json
{
  "visibility": {
    "level": "private"
  }
}
```

### Public Visibility

Anyone can view the data. Use with caution.

```json
{
  "visibility": {
    "level": "public"
  }
}
```

### Unlisted Visibility

Only accessible via a link containing a randomly generated `unlisted_id`. The ID can be regenerated at any time to invalidate previous links.

```json
{
  "visibility": {
    "level": "unlisted",
    "unlisted_id": "a7b3c9d2e5f8g1h4",
    "unlisted_id_created_at": "2026-01-15T10:00:00Z"
  }
}
```

**Regenerating Unlisted ID:**

When the user wants to invalidate all existing unlisted links:

```json
{
  "visibility": {
    "level": "unlisted",
    "unlisted_id": "x9y8z7w6v5u4t3s2",
    "unlisted_id_created_at": "2026-02-01T12:00:00Z",
    "previous_unlisted_ids": [
      {
        "id": "a7b3c9d2e5f8g1h4",
        "invalidated_at": "2026-02-01T12:00:00Z"
      }
    ]
  }
}
```

**Unlisted URL Format:**

```
geogram://tracker/{owner_callsign}/{collection_id}/{item_type}/{item_id}?key={unlisted_id}
```

Example:
```
geogram://tracker/X1ABCD/my_fitness/paths/path_20260115_abc123?key=a7b3c9d2e5f8g1h4
```

### Restricted Visibility

Access granted to specific contacts and/or groups.

```json
{
  "visibility": {
    "level": "restricted",
    "allowed_contacts": [
      {
        "callsign": "ALICE1",
        "npub": "npub1alice...",
        "added_at": "2026-01-15T10:00:00Z"
      },
      {
        "callsign": "BOB42",
        "npub": "npub1bob...",
        "added_at": "2026-01-15T10:00:00Z"
      }
    ],
    "allowed_groups": [
      {
        "group_id": "group_family",
        "group_name": "Family",
        "added_at": "2026-01-15T10:00:00Z"
      }
    ]
  }
}
```

### Collection-Level Visibility (extra/security.json)

Set default visibility for the entire collection:

```json
{
  "default_visibility": {
    "level": "private"
  },
  "visibility_overrides": {
    "paths": {
      "level": "restricted",
      "allowed_groups": [
        {"group_id": "group_family", "group_name": "Family"}
      ]
    },
    "exercises": {
      "level": "public"
    },
    "plans": {
      "level": "unlisted",
      "unlisted_id": "m4n5o6p7q8r9s0t1"
    }
  },
  "share_settings": {
    "allow_location_sharing": true,
    "allow_proximity_detection": true,
    "blocked_callsigns": []
  },
  "export_settings": {
    "require_encryption": false,
    "allowed_formats": ["json", "csv", "gpx"]
  }
}
```

### Per-Item Visibility Override

Individual items can override collection defaults:

**Path with restricted visibility:**
```json
{
  "id": "path_20260115_abc123",
  "title": "Morning Run",
  "visibility": {
    "level": "restricted",
    "allowed_contacts": [
      {"callsign": "ALICE1", "npub": "npub1alice..."}
    ]
  }
}
```

**Exercise with unlisted visibility:**
```json
{
  "exercise_id": "running",
  "year": 2026,
  "visibility": {
    "level": "unlisted",
    "unlisted_id": "r2s3t4u5v6w7x8y9"
  },
  "entries": [...]
}
```

**Plan shared with a group:**
```json
{
  "id": "plan_fitness_2026",
  "title": "2026 Fitness Plan",
  "visibility": {
    "level": "restricted",
    "allowed_groups": [
      {"group_id": "group_gym_buddies", "group_name": "Gym Buddies"}
    ]
  }
}
```

### Visibility Inheritance

1. If an item has no `visibility` field → use collection default from `security.json`
2. If no type-specific override in `security.json` → use `default_visibility`
3. If no `default_visibility` → assume `private`

### Visibility Field Summary

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `level` | string | Yes | private, public, unlisted, restricted |
| `unlisted_id` | string | For unlisted | Random 16+ char alphanumeric ID |
| `unlisted_id_created_at` | string | For unlisted | When ID was generated |
| `previous_unlisted_ids` | array | No | History of invalidated IDs |
| `allowed_contacts` | array | For restricted | List of allowed contacts |
| `allowed_groups` | array | For restricted | List of allowed groups |

### Security Measures

1. **NOSTR Signatures** - Verify data authenticity and ownership
2. **Encrypted Export** - Optional encryption for exports
3. **Access Control** - Per-collection and per-item permissions
4. **Unlisted ID Rotation** - Invalidate shared links at any time
5. **Contact/Group Verification** - Verify access via NOSTR npub

---

## Battery Optimization

### GPS Strategies

1. **Adaptive Intervals** - Increase interval when stationary
2. **Accuracy Filtering** - Discard readings with poor accuracy
3. **Batch Processing** - Process points in batches
4. **Background Limits** - Reduce frequency in background

### Bluetooth Strategies

1. **Scan Intervals** - Configurable scan frequency
2. **Low Energy Mode** - Use BLE for minimal power
3. **Smart Scanning** - Reduce scans when alone

### Recommended Settings by Use Case

| Use Case | GPS Interval | BT Scan | Battery Impact |
|----------|--------------|---------|----------------|
| High Accuracy | 10s | 15s | High |
| Normal | 60s | 30s | Medium |
| Battery Saver | 300s | 60s | Low |
| Background | 300s | 120s | Minimal |

---

## NOSTR Integration

### Purpose

Enable verification of data authenticity using NOSTR protocol signatures.

### Signature Structure

```json
{
  "metadata": {
    "npub": "npub1abc123...",
    "created_at": "2026-01-15T12:00:00Z",
    "signature": "sig1xyz789...",
    "signed_fields": ["id", "timestamp", "value"],
    "signature_version": "1.0"
  }
}
```

### What Gets Signed

- Entry creation events
- Share configurations
- Path completion events
- Exercise session completions

### Verification Process

1. Extract signed fields from data
2. Serialize to canonical JSON
3. Hash with SHA-256
4. Verify BIP-340 Schnorr signature against npub

---

## Validation Rules

### General Rules

1. All timestamps must be valid ISO 8601 format
2. IDs must be alphanumeric, 6-32 characters
3. Callsigns must match Geogram format
4. Coordinates must be valid lat/lon ranges

### Specific Rules

| Data Type | Field | Rule |
|-----------|-------|------|
| Paths | `interval_seconds` | 10-3600 |
| Paths | `lat` | -90 to 90 |
| Paths | `lon` | -180 to 180 |
| Measurements | `value` | Within type's min/max |
| Exercises | `count` | >= 0 |
| Plans | `status` | active, paused, completed, expired, cancelled |
| Plans | `weekly_target` | > 0 |
| Plans | `daily_target` | >= 0 (if specified) |
| Sharing | `accuracy` | precise, approximate, city |
| Visits | `duration_seconds` | >= 0 |
| Visibility | `level` | private, public, unlisted, restricted |
| Visibility | `unlisted_id` | 16+ alphanumeric chars (if unlisted) |
| Visibility | `allowed_contacts` | Non-empty array (if restricted) |
| Visibility | `allowed_groups` | Non-empty array (if restricted, no contacts) |

### Required Fields by Type

| Type | Required Fields |
|------|-----------------|
| Path | id, started_at, status, interval_seconds |
| Measurement | id, timestamp, value |
| Exercise Entry | id, timestamp, count |
| Plan | id, title, status, starts_at, ends_at, goals |
| Plan Goal | id, exercise_id, target_type, weekly_target |
| Share | id, type, active, update_interval_seconds |
| Visit | id, place_id, checked_in_at, auto_detected |
| Visibility (unlisted) | level, unlisted_id |
| Visibility (restricted) | level, (allowed_contacts or allowed_groups) |

---

## Parsing Implementation

### Loading a Tracker Collection

```dart
class TrackerCollection {
  final String id;
  final TrackerMetadata metadata;
  final TrackerSettings settings;

  static Future<TrackerCollection> load(String path) async {
    final metadataFile = File('$path/metadata.json');
    final settingsFile = File('$path/settings.json');

    final metadata = TrackerMetadata.fromJson(
      jsonDecode(await metadataFile.readAsString())
    );

    final settings = TrackerSettings.fromJson(
      jsonDecode(await settingsFile.readAsString())
    );

    return TrackerCollection(
      id: metadata.id,
      metadata: metadata,
      settings: settings,
    );
  }
}
```

### Loading Paths

```dart
Future<List<TrackerPath>> loadPaths(String collectionPath) async {
  final pathsDir = Directory('$collectionPath/paths');
  final paths = <TrackerPath>[];

  await for (final yearDir in pathsDir.list()) {
    if (yearDir is Directory) {
      await for (final pathDir in yearDir.list()) {
        if (pathDir is Directory) {
          final pathFile = File('${pathDir.path}/path.json');
          if (await pathFile.exists()) {
            paths.add(TrackerPath.fromJson(
              jsonDecode(await pathFile.readAsString())
            ));
          }
        }
      }
    }
  }

  return paths..sort((a, b) => b.startedAt.compareTo(a.startedAt));
}
```

### Loading Measurements

```dart
Future<MeasurementData> loadMeasurements(
  String collectionPath,
  String typeId,
  int year,
) async {
  final file = File('$collectionPath/measurements/$year/$typeId.json');

  if (!await file.exists()) {
    return MeasurementData.empty(typeId, year);
  }

  return MeasurementData.fromJson(
    jsonDecode(await file.readAsString())
  );
}

/// Load measurements across multiple years
Future<List<MeasurementData>> loadMeasurementsAllYears(
  String collectionPath,
  String typeId,
) async {
  final measurementsDir = Directory('$collectionPath/measurements');
  final results = <MeasurementData>[];

  await for (final yearDir in measurementsDir.list()) {
    if (yearDir is Directory) {
      final year = int.tryParse(yearDir.path.split('/').last);
      if (year != null) {
        final file = File('${yearDir.path}/$typeId.json');
        if (await file.exists()) {
          results.add(MeasurementData.fromJson(
            jsonDecode(await file.readAsString())
          ));
        }
      }
    }
  }

  return results..sort((a, b) => a.year.compareTo(b.year));
}
```

### Loading Exercises

```dart
Future<ExerciseData> loadExercises(
  String collectionPath,
  String exerciseId,
  int year,
) async {
  final file = File('$collectionPath/exercises/$year/$exerciseId.json');

  if (!await file.exists()) {
    return ExerciseData.empty(exerciseId, year);
  }

  return ExerciseData.fromJson(
    jsonDecode(await file.readAsString())
  );
}
```

---

## Best Practices

### Data Management

1. **Regular Backups** - Export data periodically
2. **Cleanup Old Data** - Archive or delete old paths/logs
3. **Validate on Write** - Always validate before saving
4. **Atomic Writes** - Use temp files to prevent corruption

### Performance

1. **Lazy Loading** - Load data on demand
2. **Pagination** - Limit displayed entries
3. **Index Frequently Queried Data** - Maintain summary files
4. **Cache Statistics** - Don't recalculate constantly

### User Experience

1. **Clear Feedback** - Show recording status clearly
2. **Battery Warnings** - Alert when tracking drains battery
3. **Privacy Reminders** - Remind about active shares
4. **Goal Progress** - Show progress toward targets

---

## Related Documentation

- [Places Format Specification](places-format-specification.md) - For place definitions used in visits
- [Contacts Format Specification](contacts-format-specification.md) - For contact references in sharing/proximity
- [Groups Format Specification](groups-format-specification.md) - For group definitions in sharing
- [Events Format Specification](events-format-specification.md) - For event integration with exercises

---

## Change Log

### Version 1.0.0 (2026-01-07)

- Initial specification
- Paths tracking with GPS
- Measurements tracking (weight, blood pressure, etc.)
- Exercise tracking (cardio and strength)
- Location sharing (group and temporary)
- Bluetooth proximity tracking
- Place visits (check-in/checkout)
- NOSTR integration for signatures
- Battery optimization guidelines
