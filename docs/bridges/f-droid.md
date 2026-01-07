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

## Publishing a New Version

### Step 1: Create a Release Tag in Geogram

```bash
cd /home/brito/code/geograms/geogram

# Update version in pubspec.yaml
# version: X.Y.Z+BUILD

# Commit changes
git add -A
git commit -m "Release vX.Y.Z"

# Create and push tag
git tag vX.Y.Z
git push origin main --tags
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

1. Add new build entry under `Builds:`:
   ```yaml
   Builds:
     - versionName: X.Y.Z
       versionCode: N  # Increment from previous
       commit: vX.Y.Z
       # ... rest of build config
   ```

2. Update bottom section:
   ```yaml
   CurrentVersion: X.Y.Z
   CurrentVersionCode: N
   ```

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
