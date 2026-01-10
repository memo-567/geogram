import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/tracker_proximity_track.dart';
import '../services/tracker_service.dart';
import '../widgets/tracker_map_card.dart';
import '../../services/i18n_service.dart';
import '../../services/location_provider_service.dart';

/// Detail page for a proximity track showing map with contact locations.
class ProximityDetailPage extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;
  final ProximityTrack track;
  final int year;
  final int week;

  const ProximityDetailPage({
    super.key,
    required this.service,
    required this.i18n,
    required this.track,
    required this.year,
    required this.week,
  });

  @override
  State<ProximityDetailPage> createState() => _ProximityDetailPageState();
}

class _ProximityDetailPageState extends State<ProximityDetailPage> {
  late List<_ContactCluster> _clusters;
  late List<ProximityEntry> _allEntries;
  late bool _hasLocationData;

  @override
  void initState() {
    super.initState();
    // Sort entries by timestamp descending (most recent first)
    _allEntries = List<ProximityEntry>.from(widget.track.entries)
      ..sort((a, b) => b.timestampDateTime.compareTo(a.timestampDateTime));
    _clusters = _clusterContacts(_allEntries);
    _hasLocationData = _clusters.isNotEmpty;
  }

  /// Cluster nearby contact locations (within 50 meters)
  List<_ContactCluster> _clusterContacts(List<ProximityEntry> entries) {
    if (entries.isEmpty) return [];

    final clusters = <_ContactCluster>[];
    const clusterRadiusMeters = 50.0;

    for (final entry in entries) {
      // Skip entries with no valid location
      if (entry.lat == 0.0 && entry.lon == 0.0) continue;

      bool addedToCluster = false;

      // Try to add to existing cluster
      for (final cluster in clusters) {
        final distance = _calculateDistance(
          cluster.centerLat,
          cluster.centerLon,
          entry.lat,
          entry.lon,
        );

        if (distance <= clusterRadiusMeters) {
          cluster.addEntry(entry);
          addedToCluster = true;
          break;
        }
      }

      // Create new cluster if not added to existing
      if (!addedToCluster) {
        clusters.add(_ContactCluster(entry));
      }
    }

    // Sort by total duration (most time first)
    clusters.sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));

    return clusters;
  }

  /// Calculate distance between two coordinates in meters (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Format seconds into human-readable duration
  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) {
      return totalSeconds == 1 ? '1 second' : '$totalSeconds seconds';
    }

    final totalMinutes = totalSeconds ~/ 60;
    if (totalMinutes < 60) {
      return totalMinutes == 1 ? '1 minute' : '$totalMinutes minutes';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours < 24) {
      final hourText = hours == 1 ? '1 hour' : '$hours hours';
      if (minutes == 0) return hourText;
      final minuteText = minutes == 1 ? '1 minute' : '$minutes minutes';
      return '$hourText and $minuteText';
    }

    final days = hours ~/ 24;
    final remainingHours = hours % 24;
    final dayText = days == 1 ? '1 day' : '$days days';
    if (remainingHours == 0) return dayText;
    final hourText = remainingHours == 1 ? '1 hour' : '$remainingHours hours';
    return '$dayText and $hourText';
  }

  void _showClusterDetails(_ContactCluster cluster) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => _buildClusterBottomSheet(
          cluster,
          scrollController,
        ),
      ),
    );
  }

  Widget _buildClusterBottomSheet(
    _ContactCluster cluster,
    ScrollController scrollController,
  ) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.MMMd().add_jm();

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contact Location',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${cluster.centerLat.toStringAsFixed(5)}, ${cluster.centerLon.toStringAsFixed(5)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.access_time,
                    label: 'Time together',
                    value: _formatDuration(cluster.totalSeconds),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.repeat,
                    label: 'Contacts',
                    value: '${cluster.entries.length}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Time range
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${dateFormat.format(cluster.firstDetection.toLocal())} - '
                      '${dateFormat.format(cluster.lastDetection.toLocal())}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Contact list header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Contact sessions',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Contact list items
          ...cluster.entries.map((entry) {
            final time = entry.timestampDateTime.toLocal();
            final duration = entry.durationSeconds ?? 60;

            return ListTile(
              dense: true,
              leading: const Icon(Icons.circle, size: 8),
              title: Text(dateFormat.format(time)),
              trailing: Text(
                _formatDuration(duration),
                style: theme.textTheme.bodySmall,
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return _clusters.asMap().entries.map((entry) {
      final index = entry.key;
      final cluster = entry.value;

      // Color based on duration (more time = more intense)
      final maxSeconds = _clusters.isNotEmpty
          ? _clusters.map((c) => c.totalSeconds).reduce(math.max)
          : 1;
      final intensity = cluster.totalSeconds / maxSeconds;
      final color = Color.lerp(Colors.blue, Colors.red, intensity) ?? Colors.blue;

      return Marker(
        point: LatLng(cluster.centerLat, cluster.centerLon),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _showClusterDetails(cluster),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDevice = widget.track.type == ProximityTargetType.device;
    final icon = isDevice ? Icons.bluetooth : Icons.place;
    final totalDuration = _formatDuration(widget.track.weekSummary.totalSeconds);

    // Get all points for map bounds
    final points = _clusters
        .map((c) => LatLng(c.centerLat, c.centerLon))
        .toList();

    // Get fallback center from current location
    final currentPos = LocationProviderService().currentPosition;
    final fallbackCenter = currentPos != null
        ? LatLng(currentPos.latitude, currentPos.longitude)
        : const LatLng(0, 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.track.displayName),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, size: 40, color: isDevice ? Colors.blue : Colors.green),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.displayName,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    totalDuration,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.near_me, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.track.weekSummary.totalEntries} contacts',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Map section (always shown)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Contact locations',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TrackerMapCard(
                points: points,
                markers: _buildMarkers(),
                height: 300,
                showTransportLabels: true,
                fallbackCenter: fallbackCenter,
              ),
            ),
            const SizedBox(height: 8),
            if (_hasLocationData)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tap a marker to see details',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            // Location clusters list (only if we have clusters)
            if (_clusters.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Locations (${_clusters.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _clusters.length,
                itemBuilder: (context, index) {
                  final cluster = _clusters[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(_formatDuration(cluster.totalSeconds)),
                      subtitle: Text('${cluster.entries.length} contacts'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showClusterDetails(cluster),
                    ),
                  );
                },
              ),
            ],

            // Contact sessions list (always shown)
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Contact sessions (${_allEntries.length})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _allEntries.length,
              itemBuilder: (context, index) {
                final entry = _allEntries[index];
                final time = entry.timestampDateTime.toLocal();
                final duration = entry.durationSeconds ?? 60;
                final dateFormat = DateFormat.MMMd().add_jm();

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      Icons.access_time,
                      color: Colors.blue[400],
                    ),
                    title: Text(dateFormat.format(time)),
                    trailing: Text(
                      _formatDuration(duration),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// A cluster of nearby contact entries
class _ContactCluster {
  final List<ProximityEntry> entries = [];
  double _sumLat = 0;
  double _sumLon = 0;

  _ContactCluster(ProximityEntry firstEntry) {
    addEntry(firstEntry);
  }

  void addEntry(ProximityEntry entry) {
    entries.add(entry);
    _sumLat += entry.lat;
    _sumLon += entry.lon;
  }

  double get centerLat => _sumLat / entries.length;
  double get centerLon => _sumLon / entries.length;

  int get totalSeconds => entries.fold(0, (sum, e) => sum + (e.durationSeconds ?? 60));

  DateTime get firstDetection {
    return entries
        .map((e) => e.timestampDateTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime get lastDetection {
    return entries.map((e) {
      if (e.endedAtDateTime != null) return e.endedAtDateTime!;
      return e.timestampDateTime;
    }).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

/// A simple stat card widget
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
