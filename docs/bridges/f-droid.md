# F-Droid Publishing

This document describes how to publish and update Geogram on F-Droid.

## Repository Structure

- **Source repo**: https://github.com/geograms/geogram
- **F-Droid metadata fork**: https://gitlab.com/brito500/fdroiddata
- **Upstream F-Droid**: https://gitlab.com/fdroid/fdroiddata
- **Metadata file**: `metadata/dev.geogram.yml`

## Prerequisites

1. Clone the fdroiddata fork:
   ```bash
   cd /home/brito/code/geograms
   git clone git@gitlab.com:brito500/fdroiddata.git
   cd fdroiddata
   git remote add upstream https://gitlab.com/fdroid/fdroiddata.git
   git remote add myfork git@gitlab.com:brito500/fdroiddata.git
   ```

2. Ensure you have the `add-geogram` branch:
   ```bash
   git checkout add-geogram
   ```

## Publishing a New Version (Auto-Update with Tag Filter)

F-Droid is configured to automatically pick up versions tagged with `fdroid-v*` pattern.
This lets you release frequently on GitHub while controlling exactly which versions reach F-Droid.

### How It Works

| Tag | F-Droid Action |
|-----|----------------|
| `v1.7.10` | Ignored |
| `v1.7.11` | Ignored |
| `fdroid-v1.7.12` | Auto-picked up for F-Droid |

### Releasing to F-Droid

```bash
cd /home/brito/code/geograms/geogram

# 1. Ensure pubspec.yaml has the correct version (e.g., version: 1.7.12+BUILD)

# 2. Update .flutter-version if Flutter version changed
echo "3.38.5" > .flutter-version

# 3. Commit if needed
git add -A
git commit -m "Release v1.7.12"
git push origin main

# 4. Create the F-Droid tag (this triggers F-Droid auto-update)
git tag fdroid-v1.7.12
git push origin fdroid-v1.7.12
```

That's it. F-Droid will automatically detect the new `fdroid-v*` tag and build it.

### Version Naming

- The tag must match pattern `fdroid-vX.Y.Z`
- The version number must match `pubspec.yaml` version field
- Example: if pubspec.yaml has `version: 1.7.12+50`, tag as `fdroid-v1.7.12`

## Manual Version Update (Alternative)

If auto-update is not working or you need to manually add a version:

### Step 1: Create a Release Tag in Geogram

```bash
cd /home/brito/code/geograms/geogram

# Get the commit hash for F-Droid (use hash, not tag name)
git rev-parse fdroid-v1.7.12
```

### Step 2: Update F-Droid Metadata

```bash
cd /home/brito/code/geograms/fdroiddata
git checkout add-geogram

# Sync with upstream first
git fetch upstream
git rebase upstream/master
```

Edit `metadata/dev.geogram.yml`:

1. Add new build entry under `Builds:` (use **commit hash**, not tag):
   ```yaml
   Builds:
     - versionName: X.Y.Z
       versionCode: N  # Increment from previous
       commit: abc123def456...  # Full commit hash from git rev-parse
       # ... rest of build config
   ```

2. Update bottom section:
   ```yaml
   CurrentVersion: X.Y.Z
   CurrentVersionCode: N
   ```

**Important**: Always use the full commit hash, not the tag name (e.g., `commit: a38826fa245fe6e4c0be2e9a39169b170027b93b` instead of `commit: v1.6.101`).

### Step 3: Push and Create/Update MR

```bash
git add metadata/dev.geogram.yml
git commit -m "Update dev.geogram to vX.Y.Z"
git push myfork add-geogram
```

The MR will be automatically updated: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/31380

## Build Configuration

The F-Droid build requires special handling for:

### Removed Directories
```yaml
rm:
  - ios
  - macos
  - windows
  - linux
  - web
  - geogram-cli
  - bin
  - android/tinyemu
  - android/app/src/main/jniLibs
  - third_party/flutter_webrtc/third_party/libwebrtc/lib
```

### Prebuild Steps

1. **Remove proprietary dependencies**:
   ```bash
   sed -i -e '/tinyemu/d' -e '/flutter_map_tile_caching/d' pubspec.yaml
   ```

2. **Patch map tile service** (removes FMTC caching):
   ```bash
   sed -i -e "/import 'package:flutter_map_tile_caching/d" \
          -e 's/fmtc\.FMTCStore?/Object?/g' \
          -e '/FMTCObjectBoxBackend/,/);/d' \
          -e '/_tileStore = fmtc\./d' \
          -e '/_tileStore!\.manage/d' \
          lib/services/map_tile_service.dart
   ```

3. **Remove Google Play Services from geolocator**:
   ```bash
   cd $PUB_CACHE/hosted/pub.dev/geolocator_android-*/android
   sed -i -e '/gms/d' build.gradle
   cd src/main/java/com/baseflow/geolocator/location
   rm FusedLocationClient.java
   sed -i -e '/if (forceAndroidLocationManager) {/,/^  }/c return new LocationManagerClient(context, locationOptions);}' \
          -e '/isGooglePlayServicesAvailable/,/^  }/d' \
          -e '/gms/d' GeolocationManager.java
   ```

## Compliance Requirements

F-Droid requires:

1. **No Google Play Services** - All GMS dependencies must be removed or stubbed
2. **No proprietary blobs** - Remove prebuilt binaries (jniLibs, etc.)
3. **No dependency metadata** - Set in `android/app/build.gradle.kts`:
   ```kotlin
   dependenciesInfo {
       includeInApk = false
       includeInBundle = false
   }
   ```
4. **Clean proguard rules** - No Google Play Core references

## Triggering a Rebuild

To trigger F-Droid to re-scan without changing version:

```bash
cd /home/brito/code/geograms/fdroiddata
git checkout add-geogram

# Make a trivial change (add newline, update comment, etc.)
echo "" >> metadata/dev.geogram.yml

git add metadata/dev.geogram.yml
git commit -m "Trigger rebuild for dev.geogram"
git push myfork add-geogram
```

## Monitoring Build Status

1. Check the MR pipeline: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/31380
2. Look for the `fdroid build` job in the pipeline
3. Review logs for any build failures

## Common Issues

### "DependencyInfoBlock" Error
Add to `android/app/build.gradle.kts`:
```kotlin
dependenciesInfo {
    includeInApk = false
    includeInBundle = false
}
```

### Google Play Services References
Ensure all gms/play-services references are removed from:
- `pubspec.yaml`
- `android/app/build.gradle.kts`
- `android/app/proguard-rules.pro`

### Flutter Version Mismatch
Update `srclibs` in metadata to match required Flutter version:
```yaml
srclibs:
  - flutter@3.38.5
```

Also update `.flutter-version` in the geogram repo to keep versions in sync.

### Google Play Core Classes in DEX
If the build fails with Play Core class errors, the issue is usually in ProGuard rules keeping classes that reference Play Core. R8 should strip them automatically.

**Fix**: Simplify `android/app/proguard-rules.pro` - remove unnecessary Flutter/Dart rules:
```proguard
# Suppress warnings for Play Core classes (not included in F-Droid builds)
-dontwarn com.google.android.play.core.**

# TensorFlow Lite rules
-keep class org.tensorflow.** { *; }
-keep interface org.tensorflow.** { *; }
-dontwarn org.tensorflow.**
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# ONNX Runtime rules
-keep class ai.onnxruntime.** { *; }

# Keep TFLite Flutter plugin
-keep class com.tfliteflutter.** { *; }
-dontwarn com.tfliteflutter.**
```

**Important**: Do NOT add `-keep class io.flutter.**` or similar Flutter rules - this prevents R8 from stripping unused Play Core references.

## Auto Update Configuration

The metadata uses tag-filtered automatic updates:
```yaml
AutoUpdateMode: Version
UpdateCheckMode: Tags ^fdroid-v.*$
```

This tells F-Droid to:
- Only check for tags matching `^fdroid-v.*$` pattern (e.g., `fdroid-v1.7.12`)
- Ignore regular version tags (e.g., `v1.7.12`)
- Auto-generate build entries for matching tags

### Why Tag Filtering?

During active development, Geogram may have 3-5 releases per day. Tag filtering allows:
- Frequent releases on GitHub for testers using the auto-updater
- Controlled releases to F-Droid users (only `fdroid-v*` tags)
- No manual metadata editing required for F-Droid updates

## Files to Maintain

### In Geogram Repo
- `.flutter-version` - Pin Flutter version (e.g., `3.38.5`)
- `android/app/proguard-rules.pro` - Keep minimal, let R8 strip unused code
- `android/app/build.gradle.kts` - Include `dependenciesInfo { includeInApk = false }`

### In F-Droid Metadata
- Use commit hashes, not tags
- Keep prebuild scripts to patch GMS dependencies
- Enable auto update for future versions
