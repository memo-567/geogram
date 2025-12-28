/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/event.dart';
import '../models/place.dart';
import '../models/map_item.dart';
import '../models/collection.dart';
import 'collection_service.dart';
import 'event_service.dart';
import 'place_service.dart';
import 'news_service.dart';
import 'report_service.dart';
import 'station_service.dart';
import 'station_alert_service.dart';
import 'station_place_service.dart';
import 'contact_service.dart';
import 'profile_service.dart';
import 'log_service.dart';
import 'storage_config.dart';

/// Service for aggregating and filtering map items from all sources
class MapsService {
  static final MapsService _instance = MapsService._internal();
  factory MapsService() => _instance;
  MapsService._internal();

  // Cache for collections
  List<Collection>? _cachedCollections;
  DateTime? _cacheTimestamp;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Cache for station events
  List<Event>? _cachedStationEvents;
  DateTime? _stationEventsTimestamp;
  static const Duration _stationEventsCacheDuration = Duration(minutes: 5);

  final Map<String, (double, double)> _placeCoordinatesCache = {};

  /// Get collections with caching
  Future<List<Collection>> _getCollections({bool forceRefresh = false}) async {
    final now = DateTime.now();

    // Return cached collections if valid
    if (!forceRefresh &&
        _cachedCollections != null &&
        _cacheTimestamp != null &&
        now.difference(_cacheTimestamp!) < _cacheDuration) {
      LogService().log('MapsService: Using cached collections (${_cachedCollections!.length} items)');
      return _cachedCollections!;
    }

    // Load fresh collections
    LogService().log('MapsService: Loading fresh collections...');
    _cachedCollections = await CollectionService().loadCollections();
    _cacheTimestamp = now;
    LogService().log('MapsService: Cached ${_cachedCollections!.length} collections');

    return _cachedCollections!;
  }

  /// Clear the collections cache
  void clearCache() {
    _cachedCollections = null;
    _cacheTimestamp = null;
    _cachedStationEvents = null;
    _stationEventsTimestamp = null;
    _placeCoordinatesCache.clear();
    LogService().log('MapsService: Cache cleared');
  }

  /// Load all map items within a radius from the center point
  /// Returns items sorted by distance
  Future<List<MapItem>> loadAllMapItems({
    required double centerLat,
    required double centerLon,
    double? radiusKm,
    Set<MapItemType>? visibleTypes,
    String? languageCode,
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];
    final localRelativePaths = <String>{};
    final types = visibleTypes ?? MapItemType.values.toSet();

    LogService().log('MapsService: Loading map items within ${radiusKm ?? "unlimited"} km of ($centerLat, $centerLon)');

    // Load items from each service in parallel
    final futures = <Future<List<MapItem>>>[];

    if (types.contains(MapItemType.event)) {
      futures.add(_loadEvents(centerLat, centerLon, radiusKm, forceRefresh: forceRefresh));
    }
    if (types.contains(MapItemType.place)) {
      futures.add(_loadPlaces(centerLat, centerLon, radiusKm, forceRefresh: forceRefresh));
    }
    if (types.contains(MapItemType.news)) {
      futures.add(_loadNews(centerLat, centerLon, radiusKm, languageCode, forceRefresh: forceRefresh));
    }
    if (types.contains(MapItemType.alert)) {
      futures.add(_loadReports(centerLat, centerLon, radiusKm, languageCode, forceRefresh: forceRefresh));
    }
    if (types.contains(MapItemType.station)) {
      futures.add(_loadStations(centerLat, centerLon, radiusKm));
    }
    if (types.contains(MapItemType.contact)) {
      futures.add(_loadContacts(centerLat, centerLon, radiusKm, forceRefresh: forceRefresh));
    }

    final results = await Future.wait(futures);
    for (var result in results) {
      items.addAll(result);
    }

    // Sort by distance
    items.sort((a, b) {
      final distA = a.distanceKm ?? double.infinity;
      final distB = b.distanceKm ?? double.infinity;
      return distA.compareTo(distB);
    });

    LogService().log('MapsService: Loaded ${items.length} total map items');
    return items;
  }

  /// Load events with coordinates from all event collections
  Future<List<MapItem>> _loadEvents(
    double centerLat,
    double centerLon,
    double? radiusKm, {
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];
    final localEventKeys = <String>{};
    final now = DateTime.now();

    try {
      // Get all collections and filter for events type
      final collections = await _getCollections(forceRefresh: forceRefresh);
      final eventCollections = collections.where((c) => c.type == 'events').toList();

      LogService().log('MapsService: Found ${eventCollections.length} event collections');

      for (var collection in eventCollections) {
        if (collection.storagePath == null) continue;

        try {
          final eventService = EventService();
          await eventService.initializeCollection(collection.storagePath!);

          final events = await eventService.loadEvents();

          for (var event in events) {
            if (!_isEventCurrentOrUpcoming(event, now)) continue;
            final coords = await _resolveEventCoordinates(
              event,
              collectionPath: collection.storagePath,
            );
            if (coords == null) continue;
            final (lat, lon) = coords;

            final distance = MapItem.calculateDistance(
              centerLat,
              centerLon,
              lat,
              lon,
            );

            if (radiusKm != null && distance > radiusKm) continue;

            items.add(MapItem.fromEvent(
              event,
              distanceKm: distance,
              collectionPath: collection.storagePath,
              latitude: lat,
              longitude: lon,
            ));
            localEventKeys.add(_buildEventKey(event));
          }

          LogService().log('MapsService: Loaded ${events.length} events from ${collection.title}');
        } catch (e) {
          LogService().log('MapsService: Error loading events from ${collection.title}: $e');
        }
      }

      // Load station events (public events from station)
      try {
        final stationEvents = await _getStationEvents(forceRefresh: forceRefresh);

        for (final event in stationEvents) {
          if (!_isEventCurrentOrUpcoming(event, now)) continue;
          final coords = await _resolveEventCoordinates(event);
          if (coords == null) continue;
          final (lat, lon) = coords;

          final eventKey = _buildEventKey(event);
          if (localEventKeys.contains(eventKey)) {
            continue;
          }

          final distance = MapItem.calculateDistance(
            centerLat,
            centerLon,
            lat,
            lon,
          );

          if (radiusKm != null && distance > radiusKm) continue;

          items.add(MapItem.fromEvent(
            event,
            distanceKm: distance,
            collectionPath: null,
            isFromStation: true,
            idOverride: eventKey.isNotEmpty ? eventKey : null,
            latitude: lat,
            longitude: lon,
          ));
        }

        LogService().log('MapsService: Added ${stationEvents.length} station events to map');
      } catch (e) {
        LogService().log('MapsService: Error loading station events: $e');
      }

      LogService().log('MapsService: Found ${items.length} total events with coordinates');
    } catch (e) {
      LogService().log('MapsService: Error loading events: $e');
    }

    return items;
  }

  bool _isEventCurrentOrUpcoming(Event event, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = _parseEventDate(event.startDate);
    final end = _parseEventDate(event.endDate);

    if (start != null && end != null && !start.isAtSameMomentAs(end)) {
      return !end.isBefore(today);
    }

    final singleDate = start ?? end;
    final eventDate = singleDate ?? DateTime(event.dateTime.year, event.dateTime.month, event.dateTime.day);
    return !eventDate.isBefore(today);
  }

  DateTime? _parseEventDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final dt = DateTime.parse(value);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (e) {
      return null;
    }
  }

  String _buildEventKey(Event event) {
    final author = event.author.trim();
    if (author.isEmpty) return event.id;
    return '${author.toUpperCase()}:${event.id}';
  }

  Future<(double, double)?> _resolveEventCoordinates(
    Event event, {
    String? collectionPath,
  }) async {
    final placePath = event.placePath;
    if (placePath != null && placePath.isNotEmpty) {
      final resolvedPlacePath = _resolvePlacePath(
        placePath,
        collectionPath,
        author: event.author,
      );
      if (resolvedPlacePath == null || resolvedPlacePath.isEmpty) return null;

      final cached = _placeCoordinatesCache[resolvedPlacePath];
      if (cached != null) return cached;

      final place = await _loadPlaceFromPath(resolvedPlacePath);
      if (place == null) return null;
      final coords = (place.latitude, place.longitude);
      _placeCoordinatesCache[resolvedPlacePath] = coords;
      return coords;
    }

    if (event.hasCoordinates) {
      final lat = event.latitude;
      final lon = event.longitude;
      if (lat != null && lon != null) {
        return (lat, lon);
      }
    }

    return null;
  }

  String? _resolvePlacePath(
    String placePath,
    String? collectionPath, {
    String? author,
  }) {
    if (placePath.isEmpty) return null;
    if (path.isAbsolute(placePath)) return placePath;
    if (collectionPath != null && collectionPath.isNotEmpty) {
      final basePath = path.dirname(collectionPath);
      return path.normalize(path.join(basePath, placePath));
    }
    if (StorageConfig().isInitialized) {
      final callsign = (author != null && author.isNotEmpty)
          ? author
          : ProfileService().getProfile().callsign;
      if (callsign.isNotEmpty) {
        final basePath = StorageConfig().getCallsignDir(callsign);
        return path.normalize(path.join(basePath, placePath));
      }
    }
    return null;
  }

  Future<Place?> _loadPlaceFromPath(String folderPath) async {
    if (kIsWeb) return null;
    try {
      final placeFile = File(path.join(folderPath, 'place.txt'));
      if (!await placeFile.exists()) return null;
      final content = await placeFile.readAsString();
      return PlaceService().parsePlaceContent(
        content: content,
        filePath: placeFile.path,
        folderPath: folderPath,
      );
    } catch (e) {
      LogService().log('MapsService: Error loading place from $folderPath: $e');
      return null;
    }
  }

  Future<List<Event>> _getStationEvents({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedStationEvents != null &&
        _stationEventsTimestamp != null &&
        now.difference(_stationEventsTimestamp!) < _stationEventsCacheDuration) {
      return _cachedStationEvents!;
    }

    try {
      final stationService = StationService();
      if (!stationService.isInitialized) {
        await stationService.initialize();
      }

      final preferred = stationService.getPreferredStation();
      final station = (preferred != null && preferred.url.isNotEmpty)
          ? preferred
          : stationService.getConnectedRelay();
      if (station == null || station.url.isEmpty) {
        LogService().log('MapsService: No station configured for events');
        return _cachedStationEvents ?? [];
      }

      var baseUrl = station.url;
      if (baseUrl.startsWith('wss://')) {
        baseUrl = baseUrl.replaceFirst('wss://', 'https://');
      } else if (baseUrl.startsWith('ws://')) {
        baseUrl = baseUrl.replaceFirst('ws://', 'http://');
      }

      final baseUri = Uri.parse(baseUrl);
      final uri = baseUri.replace(
        pathSegments: [...baseUri.pathSegments, 'api', 'events'],
      );

      LogService().log('MapsService: Fetching station events from $uri');

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        LogService().log('MapsService: Station events fetch failed: HTTP ${response.statusCode}');
        return _cachedStationEvents ?? [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final eventsJson = json['events'] as List<dynamic>? ?? [];
      final events = <Event>[];

      for (final eventData in eventsJson) {
        if (eventData is! Map<String, dynamic>) continue;
        try {
          events.add(Event.fromApiJson(eventData));
        } catch (e) {
          LogService().log('MapsService: Error parsing station event: $e');
        }
      }

      _cachedStationEvents = events;
      _stationEventsTimestamp = now;
      return events;
    } catch (e) {
      LogService().log('MapsService: Error fetching station events: $e');
      return _cachedStationEvents ?? [];
    }
  }

  /// Load places from all places collections
  Future<List<MapItem>> _loadPlaces(
    double centerLat,
    double centerLon,
    double? radiusKm, {
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];
    final localRelativePaths = <String>{};

    try {
      // Get all collections and filter for places type
      final collections = await _getCollections(forceRefresh: forceRefresh);
      final placeCollections = collections.where((c) => c.type == 'places').toList();

      LogService().log('MapsService: Found ${placeCollections.length} place collections');

      for (var collection in placeCollections) {
        if (collection.storagePath == null) continue;

        try {
          final placeService = PlaceService();
          await placeService.initializeCollection(collection.storagePath!);

          final places = await placeService.loadAllPlaces();

          final basePath = path.join(collection.storagePath!, 'places');

          for (var place in places) {
            final distance = MapItem.calculateDistance(
              centerLat,
              centerLon,
              place.latitude,
              place.longitude,
            );

            if (radiusKm != null && distance > radiusKm) continue;

            items.add(MapItem.fromPlace(place, distanceKm: distance, collectionPath: collection.storagePath));

            final folderPath = place.folderPath;
            if (folderPath != null && folderPath.isNotEmpty) {
              final relativePath = path.relative(folderPath, from: basePath);
              if (!relativePath.startsWith('..')) {
                localRelativePaths.add(relativePath);
              }
            }
          }

          LogService().log('MapsService: Loaded ${places.length} places from ${collection.title}');
        } catch (e) {
          LogService().log('MapsService: Error loading places from ${collection.title}: $e');
        }
      }

      // Load station places (from other devices via the station)
      try {
        final stationPlaceService = StationPlaceService();
        final stationResult = await stationPlaceService.fetchPlaces(
          lat: centerLat,
          lon: centerLon,
          radiusKm: null,
          useSince: false,
        );

        if (stationResult.success) {
          final profile = ProfileService().getProfile();
          final localCallsign = profile.callsign.toUpperCase();
          final storageConfig = StorageConfig();
          final devicesDir = storageConfig.isInitialized ? storageConfig.devicesDir : null;

          for (final entry in stationResult.places) {
            if (localCallsign.isNotEmpty &&
                entry.callsign == localCallsign &&
                entry.relativePath != null &&
                localRelativePaths.contains(entry.relativePath)) {
              continue;
            }

            final place = entry.place;

            final distance = MapItem.calculateDistance(
              centerLat,
              centerLon,
              place.latitude,
              place.longitude,
            );

            if (radiusKm != null && distance > radiusKm) continue;

            final collectionPath =
                devicesDir != null ? path.join(devicesDir, entry.callsign) : _collectionPathFromFolder(place.folderPath);

            if (collectionPath == null || collectionPath.isEmpty) {
              continue;
            }

            items.add(MapItem(
              type: MapItemType.place,
              id: '${entry.callsign}:${place.placeFolderName}',
              title: place.name,
              subtitle: place.type ?? place.address,
              latitude: place.latitude,
              longitude: place.longitude,
              distanceKm: distance,
              sourceItem: place,
              collectionPath: collectionPath,
              isFromStation: true,
            ));
          }

          LogService().log('MapsService: Added ${stationResult.places.length} station places to map');
        } else if (stationResult.error != null) {
          LogService().log('MapsService: Station places fetch error: ${stationResult.error}');
        }
      } catch (e) {
        LogService().log('MapsService: Error loading station places: $e');
      }

      LogService().log('MapsService: Found ${items.length} total places (local + station)');
    } catch (e) {
      LogService().log('MapsService: Error loading places: $e');
    }

    return items;
  }

  String? _collectionPathFromFolder(String? folderPath) {
    if (folderPath == null || folderPath.isEmpty) return null;
    final parts = path.split(folderPath);
    final placesIndex = parts.lastIndexOf('places');
    if (placesIndex <= 0) return null;
    return path.joinAll(parts.sublist(0, placesIndex));
  }

  /// Load news articles with location from all news collections
  Future<List<MapItem>> _loadNews(
    double centerLat,
    double centerLon,
    double? radiusKm,
    String? languageCode, {
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];

    try {
      // Get all collections and filter for news type
      final collections = await _getCollections(forceRefresh: forceRefresh);
      final newsCollections = collections.where((c) => c.type == 'news').toList();

      LogService().log('MapsService: Found ${newsCollections.length} news collections');

      for (var collection in newsCollections) {
        if (collection.storagePath == null) continue;

        try {
          final newsService = NewsService();
          await newsService.initializeCollection(collection.storagePath!);

          final articles = await newsService.loadArticles(includeExpired: false);

          for (var article in articles) {
            if (!article.hasLocation) continue;

            final distance = MapItem.calculateDistance(
              centerLat,
              centerLon,
              article.latitude!,
              article.longitude!,
            );

            if (radiusKm != null && distance > radiusKm) continue;

            items.add(MapItem.fromNews(article, distanceKm: distance, languageCode: languageCode, collectionPath: collection.storagePath));
          }

          LogService().log('MapsService: Loaded ${articles.length} news from ${collection.title}');
        } catch (e) {
          LogService().log('MapsService: Error loading news from ${collection.title}: $e');
        }
      }

      LogService().log('MapsService: Found ${items.length} total news with location');
    } catch (e) {
      LogService().log('MapsService: Error loading news: $e');
    }

    return items;
  }

  /// Load reports from all report collections and station alerts
  Future<List<MapItem>> _loadReports(
    double centerLat,
    double centerLon,
    double? radiusKm,
    String? languageCode, {
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];
    final addedFolderNames = <String>{}; // Track added alerts to avoid duplicates

    try {
      // Get all collections and filter for alerts type
      final collections = await _getCollections(forceRefresh: forceRefresh);
      final reportCollections = collections.where((c) => c.type == 'alerts').toList();

      LogService().log('MapsService: Found ${reportCollections.length} alerts collections');

      // Load local alerts from collections
      for (var collection in reportCollections) {
        if (collection.storagePath == null) continue;

        try {
          // Initialize ReportService for this collection
          final reportService = ReportService();
          await reportService.initializeCollection(collection.storagePath!);

          final reports = await reportService.loadReports(includeExpired: false);

          for (var report in reports) {
            final distance = MapItem.calculateDistance(
              centerLat,
              centerLon,
              report.latitude,
              report.longitude,
            );

            if (radiusKm != null && distance > radiusKm) continue;

            items.add(MapItem.fromAlert(report, distanceKm: distance, languageCode: languageCode, collectionPath: collection.storagePath));
            addedFolderNames.add(report.folderName);
          }

          LogService().log('MapsService: Loaded ${reports.length} reports from ${collection.title}');
        } catch (e) {
          LogService().log('MapsService: Error loading reports from ${collection.title}: $e');
        }
      }

      // Load station alerts (from other devices via the station)
      try {
        final stationAlertService = StationAlertService();

        // Load cached alerts first (in case we haven't fetched recently)
        await stationAlertService.loadCachedAlerts();

        // Get station alerts
        final stationAlerts = stationAlertService.cachedAlerts;

        LogService().log('MapsService: Found ${stationAlerts.length} station alerts');

        for (var report in stationAlerts) {
          // Skip if already added from local collection (avoid duplicates)
          if (addedFolderNames.contains(report.folderName)) continue;

          final distance = MapItem.calculateDistance(
            centerLat,
            centerLon,
            report.latitude,
            report.longitude,
          );

          if (radiusKm != null && distance > radiusKm) continue;

          // Mark as from station in the MapItem
          items.add(MapItem.fromAlert(
            report,
            distanceKm: distance,
            languageCode: languageCode,
            collectionPath: null, // Station alerts don't have a local collection path
            isFromStation: true,
          ));
          addedFolderNames.add(report.folderName);
        }

        LogService().log('MapsService: Added ${stationAlerts.length} station alerts to map');
      } catch (e) {
        LogService().log('MapsService: Error loading station alerts: $e');
      }

      LogService().log('MapsService: Found ${items.length} total reports (local + station)');
    } catch (e) {
      LogService().log('MapsService: Error loading reports: $e');
    }

    return items;
  }

  /// Load stations with location
  Future<List<MapItem>> _loadStations(
    double centerLat,
    double centerLon,
    double? radiusKm,
  ) async {
    final items = <MapItem>[];

    try {
      final stations = StationService().getAllStations();

      for (var station in stations) {
        if (station.latitude == null || station.longitude == null) continue;

        final distance = MapItem.calculateDistance(
          centerLat,
          centerLon,
          station.latitude!,
          station.longitude!,
        );

        if (radiusKm != null && distance > radiusKm) continue;

        items.add(MapItem.fromRelay(station, distanceKm: distance));
      }

      LogService().log('MapsService: Found ${items.length} stations with location');
    } catch (e) {
      LogService().log('MapsService: Error loading stations: $e');
    }

    return items;
  }

  /// Load contacts with location from all contacts collections
  Future<List<MapItem>> _loadContacts(
    double centerLat,
    double centerLon,
    double? radiusKm, {
    bool forceRefresh = false,
  }) async {
    final items = <MapItem>[];

    try {
      // Get all collections and filter for contacts type
      final collections = await _getCollections(forceRefresh: forceRefresh);
      final contactCollections = collections.where((c) => c.type == 'contacts').toList();

      LogService().log('MapsService: Found ${contactCollections.length} contact collections');

      for (var collection in contactCollections) {
        if (collection.storagePath == null) continue;

        try {
          final contactService = ContactService();
          await contactService.initializeCollection(collection.storagePath!);

          final contacts = await contactService.loadAllContactsRecursively();

          for (var contact in contacts) {
            // Each contact can have multiple locations
            for (var location in contact.locations) {
              if (location.latitude == null || location.longitude == null) continue;

              final distance = MapItem.calculateDistance(
                centerLat,
                centerLon,
                location.latitude!,
                location.longitude!,
              );

              if (radiusKm != null && distance > radiusKm) continue;

              items.add(MapItem.fromContact(contact, location, distanceKm: distance, collectionPath: collection.storagePath));
            }
          }

          LogService().log('MapsService: Loaded ${contacts.length} contacts from ${collection.title}');
        } catch (e) {
          LogService().log('MapsService: Error loading contacts from ${collection.title}: $e');
        }
      }

      LogService().log('MapsService: Found ${items.length} total contact locations');
    } catch (e) {
      LogService().log('MapsService: Error loading contacts: $e');
    }

    return items;
  }

  /// Get user's saved location from profile
  /// Returns (latitude, longitude) or null if not set
  (double, double)? getUserLocation() {
    try {
      final profile = ProfileService().getProfile();
      if (profile.latitude != null && profile.longitude != null) {
        return (profile.latitude!, profile.longitude!);
      }
    } catch (e) {
      LogService().log('MapsService: Error getting user location: $e');
    }
    return null;
  }

  /// Group items by type, sorted by count (non-empty first)
  Map<MapItemType, List<MapItem>> groupByType(List<MapItem> items) {
    final grouped = <MapItemType, List<MapItem>>{};

    for (var type in MapItemType.values) {
      grouped[type] = items.where((item) => item.type == type).toList();
    }

    return grouped;
  }

  /// Get types sorted by item count (non-empty first, then by count descending)
  List<MapItemType> getTypesSortedByCount(Map<MapItemType, List<MapItem>> grouped) {
    final types = MapItemType.values.toList();
    types.sort((a, b) {
      final countA = grouped[a]?.length ?? 0;
      final countB = grouped[b]?.length ?? 0;
      // Sort by count descending (non-empty first)
      return countB.compareTo(countA);
    });
    return types;
  }

  /// Filter items by radius
  List<MapItem> filterByRadius(
    List<MapItem> items,
    double centerLat,
    double centerLon,
    double radiusKm,
  ) {
    return items.where((item) {
      final distance = MapItem.calculateDistance(
        centerLat,
        centerLon,
        item.latitude,
        item.longitude,
      );
      return distance <= radiusKm;
    }).map((item) {
      // Update distance if needed
      final distance = MapItem.calculateDistance(
        centerLat,
        centerLon,
        item.latitude,
        item.longitude,
      );
      return item.copyWithDistance(distance);
    }).toList();
  }
}
