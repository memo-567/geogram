/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/place.dart';
import '../services/collection_service.dart';
import '../services/i18n_service.dart';
import '../services/location_service.dart';
import '../services/place_service.dart';

/// Result of place selection including the place and optional collection info
class PlacePickerResult {
  final Place place;
  final String? collectionTitle;
  final double? distance; // Distance in km from user's position

  const PlacePickerResult(this.place, this.collectionTitle, this.distance);
}

/// Full-screen page for picking a place from the places collection.
///
/// This is a reusable component that can be used by any app to select places.
/// Places are sorted by distance from the user's current GPS position (on mobile)
/// or IP-based location (on desktop/web).
///
/// Usage:
/// ```dart
/// final result = await Navigator.push<PlacePickerResult>(
///   context,
///   MaterialPageRoute(
///     builder: (context) => PlacePickerPage(i18n: i18n),
///   ),
/// );
/// if (result != null) {
///   // Use result.place, result.distance
/// }
/// ```
class PlacePickerPage extends StatefulWidget {
  final I18nService i18n;

  /// Optional initial position to use for distance calculation.
  /// If not provided, will attempt to get GPS position.
  final Position? initialPosition;

  const PlacePickerPage({
    super.key,
    required this.i18n,
    this.initialPosition,
  });

  @override
  State<PlacePickerPage> createState() => _PlacePickerPageState();
}

class _PlaceWithDistance {
  final Place place;
  final String? collectionTitle;
  double? distance; // In kilometers

  _PlaceWithDistance(this.place, this.collectionTitle);
}

enum _SortMode { distance, time }

class _PlacePickerPageState extends State<PlacePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<_PlaceWithDistance> _places = [];
  List<_PlaceWithDistance> _filtered = [];
  bool _isLoading = true;
  bool _isLoadingLocation = true;
  late String _langCode;
  Position? _userPosition;
  String? _locationError;
  _SortMode _sortMode = _SortMode.distance;

  @override
  void initState() {
    super.initState();
    _langCode = widget.i18n.currentLanguage.split('_').first.toUpperCase();
    _searchController.addListener(_applyFilter);
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    // Load places and location in parallel
    await Future.wait([
      _loadPlaces(),
      _loadUserLocation(),
    ]);

    // Calculate distances (needed for both sort modes to show distance badges)
    _calculateDistances();

    // Sort places based on current mode
    _sortPlaces();

    if (mounted) {
      setState(() {
        _filtered = List.from(_places);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserLocation() async {
    if (widget.initialPosition != null) {
      _userPosition = widget.initialPosition;
      _isLoadingLocation = false;
      return;
    }

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Try IP-based location as fallback
        await _tryIpLocation();
        return;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _tryIpLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _tryIpLocation();
        return;
      }

      // Get current position
      _userPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      // Try IP-based location as fallback
      await _tryIpLocation();
    }

    if (mounted) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _tryIpLocation() async {
    try {
      final ipResult = await LocationService().detectLocationViaIP();
      if (ipResult != null) {
        _userPosition = Position(
          latitude: ipResult.latitude,
          longitude: ipResult.longitude,
          timestamp: DateTime.now(),
          accuracy: 10000, // IP-based, low accuracy
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      } else {
        _locationError = widget.i18n.t('location_unavailable');
      }
    } catch (e) {
      _locationError = widget.i18n.t('location_unavailable');
    }

    if (mounted) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _loadPlaces() async {
    try {
      final collections = await CollectionService().loadCollections();
      final placeCollections = collections
          .where((c) => c.type == 'places' && c.storagePath != null)
          .toList();

      final placeService = PlaceService();
      for (final collection in placeCollections) {
        await placeService.initializeCollection(collection.storagePath!);
        final places = await placeService.loadAllPlaces();
        for (final place in places) {
          _places.add(_PlaceWithDistance(place, collection.title));
        }
      }
    } catch (e) {
      // ignore errors, just show empty state
    }
  }

  void _calculateDistances() {
    if (_userPosition == null) return;

    final locationService = LocationService();
    for (final placeWithDistance in _places) {
      placeWithDistance.distance = locationService.calculateDistance(
        _userPosition!.latitude,
        _userPosition!.longitude,
        placeWithDistance.place.latitude,
        placeWithDistance.place.longitude,
      );
    }
  }

  void _sortPlaces() {
    switch (_sortMode) {
      case _SortMode.distance:
        _sortPlacesByDistance();
        break;
      case _SortMode.time:
        _sortPlacesByTime();
        break;
    }
  }

  void _sortPlacesByDistance() {
    if (_userPosition == null) {
      // No location - sort alphabetically
      _places.sort((a, b) {
        final nameA = a.place.getName(_langCode).toLowerCase();
        final nameB = b.place.getName(_langCode).toLowerCase();
        return nameA.compareTo(nameB);
      });
      return;
    }

    // Sort by distance
    _places.sort((a, b) {
      if (a.distance == null && b.distance == null) return 0;
      if (a.distance == null) return 1;
      if (b.distance == null) return -1;
      return a.distance!.compareTo(b.distance!);
    });
  }

  void _sortPlacesByTime() {
    // Sort by created time (newest first)
    _places.sort((a, b) {
      return b.place.createdDateTime.compareTo(a.place.createdDateTime);
    });
  }

  void _toggleSortMode() {
    setState(() {
      _sortMode = _sortMode == _SortMode.distance
          ? _SortMode.time
          : _SortMode.distance;
      _sortPlaces();
      _applyFilter();
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filtered = List.from(_places);
      });
      return;
    }

    setState(() {
      _filtered = _places.where((option) {
        final place = option.place;
        // Search across multiple fields
        final searchableFields = [
          place.getName(_langCode),
          place.address ?? '',
          place.getDescription(_langCode),
          place.type ?? '',
          place.getHistory(_langCode) ?? '',
          place.regionPath ?? '',
          option.collectionTitle ?? '',
          // Also search all language variants
          ...place.names.values,
          ...place.descriptions.values,
        ];
        final searchText = searchableFields.join(' ').toLowerCase();
        return searchText.contains(query);
      }).toList();
    });
  }

  String _formatDistance(double? distanceKm) {
    if (distanceKm == null) return '';

    if (distanceKm < 1) {
      // Show in meters
      final meters = (distanceKm * 1000).round();
      return '${meters}m';
    } else if (distanceKm < 10) {
      // Show with one decimal
      return '${distanceKm.toStringAsFixed(1)}km';
    } else {
      // Show as integer
      return '${distanceKm.round()}km';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('choose_place')),
        actions: [
          if (_isLoadingLocation)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_userPosition != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: widget.i18n.t('sorted_by_distance'),
                child: Icon(
                  Icons.my_location,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else if (_locationError != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: _locationError!,
                child: Icon(
                  Icons.location_off,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.i18n.t('search_places'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Sort mode toggle
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: _toggleSortMode,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sortMode == _SortMode.distance
                            ? Icons.near_me
                            : Icons.access_time,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sortMode == _SortMode.distance
                            ? widget.i18n.t('sorted_by_distance')
                            : widget.i18n.t('sorted_by_time'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.swap_vert,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Places list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.i18n.t('no_places_found'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final option = _filtered[index];
                          final place = option.place;
                          final name = place.getName(_langCode);
                          final subtitle = place.address?.isNotEmpty == true
                              ? place.address!
                              : place.coordinatesString;
                          final distanceStr = _formatDistance(option.distance);

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.place_outlined),
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(name)),
                                if (distanceStr.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      distanceStr,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            theme.colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(subtitle),
                            trailing: option.collectionTitle != null
                                ? Text(
                                    option.collectionTitle!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(
                                context,
                                PlacePickerResult(
                                  place,
                                  option.collectionTitle,
                                  option.distance,
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
