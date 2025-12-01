import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/relay.dart';
import '../services/relay_service.dart';
import '../services/log_service.dart';
import '../services/relay_discovery_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';

class RelaysPage extends StatefulWidget {
  const RelaysPage({super.key});

  @override
  State<RelaysPage> createState() => _RelaysPageState();
}

class _RelaysPageState extends State<RelaysPage> {
  final RelayService _relayService = RelayService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();
  List<Relay> _allRelays = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRelays();
    _ensureUserLocation();
  }

  /// Ensure user location is set, auto-detect if not
  Future<void> _ensureUserLocation() async {
    try {
      final profile = _profileService.getProfile();

      // If location is already set, we're done
      if (profile.latitude != null && profile.longitude != null) {
        LogService().log('User location already set: ${profile.latitude}, ${profile.longitude}');
        return;
      }

      // Auto-detect location from IP
      LogService().log('User location not set, detecting from IP...');
      final location = await _detectLocationFromIP();

      if (location != null) {
        await _profileService.updateProfile(
          latitude: location['lat'],
          longitude: location['lon'],
          locationName: location['locationName'],
        );
        LogService().log('User location auto-detected and saved: ${location['lat']}, ${location['lon']}');

        // Reload relays to show distances
        _loadRelays();
      } else {
        LogService().log('Unable to auto-detect user location (offline?)');
      }
    } catch (e) {
      LogService().log('Error ensuring user location: $e');
    }
  }

  /// Detect location from IP address
  Future<Map<String, dynamic>?> _detectLocationFromIP() async {
    try {
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          final lat = data['lat'] as double;
          final lon = data['lon'] as double;
          final city = data['city'] as String?;
          final country = data['country'] as String?;

          return {
            'lat': lat,
            'lon': lon,
            'locationName': (city != null && country != null) ? '$city, $country' : null,
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadRelays() async {
    setState(() => _isLoading = true);

    try {
      final relays = _relayService.getAllRelays();
      setState(() {
        _allRelays = relays;
        _isLoading = false;
      });
      LogService().log('Loaded ${relays.length} relays');
    } catch (e) {
      LogService().log('Error loading relays: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addCustomRelay() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _AddRelayDialog(),
    );

    if (result != null) {
      try {
        // Auto-set as preferred if this is the first relay
        final existingRelays = _relayService.getAllRelays();
        final isFirstRelay = existingRelays.isEmpty;

        final relay = Relay(
          url: result['url']!,
          name: result['name']!,
          callsign: result['callsign'],
          description: result['description'],
          status: isFirstRelay ? 'preferred' : 'available',
          location: result['location'],
          latitude: result['latitude'] != null ? double.tryParse(result['latitude']!) : null,
          longitude: result['longitude'] != null ? double.tryParse(result['longitude']!) : null,
        );

        final added = await _relayService.addRelay(relay);

        if (mounted) {
          if (added) {
            final message = isFirstRelay
                ? 'Added ${relay.name} as preferred relay'
                : _i18n.t('added_relay', params: [relay.name]);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Relay already exists: ${relay.name}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        await _loadRelays();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('error_adding_relay', params: [e.toString()])),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _setPreferred(Relay relay) async {
    try {
      await _relayService.setPreferred(relay.url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('set_preferred_success', params: [relay.name]))),
      );
      _loadRelays();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_i18n.t('error', params: [e.toString()])),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _setBackup(Relay relay) async {
    try {
      await _relayService.setBackup(relay.url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('added_to_backup', params: [relay.name]))),
      );
      _loadRelays();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_i18n.t('error', params: [e.toString()])),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _setAvailable(Relay relay) async {
    try {
      await _relayService.setAvailable(relay.url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('removed_from_selection', params: [relay.name]))),
      );
      _loadRelays();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_i18n.t('error', params: [e.toString()])),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteRelay(Relay relay) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('delete_relay')),
        content: Text(_i18n.t('delete_relay_confirm', params: [relay.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(_i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _relayService.deleteRelay(relay.url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('deleted_relay', params: [relay.name]))),
          );
        }
        _loadRelays();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('error_deleting_relay', params: [e.toString()])),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _clearAllRelays() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('clear_all_relays_title')),
        content: Text(_i18n.t('clear_all_relays_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(_i18n.t('clear_all')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final relays = _relayService.getAllRelays();
        for (var relay in relays) {
          await _relayService.deleteRelay(relay.url);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_i18n.t('all_relays_cleared'))),
          );
        }
        _loadRelays();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('error_clearing_relays', params: [e.toString()])),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _scanNow() async {
    final results = await showDialog<List<NetworkScanResult>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NetworkScanDialog(
        relayService: _relayService,
        i18n: _i18n,
      ),
    );

    if (results != null && results.isNotEmpty) {
      _loadRelays();
    }
  }

  Future<void> _testConnection(Relay relay) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_i18n.t('connecting_to_relay', params: [relay.name])),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Use new connectRelay method with hello handshake
      final success = await _relayService.connectRelay(relay.url);
      _loadRelays();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('connected_success', params: [relay.name])),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('connection_failed')),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_i18n.t('connection_error', params: [e.toString()])),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Relay> get _selectedRelays {
    return _allRelays.where((r) => r.status == 'preferred' || r.status == 'backup').toList()
      ..sort((a, b) {
        // Preferred first
        if (a.status == 'preferred') return -1;
        if (b.status == 'preferred') return 1;
        return 0;
      });
  }

  List<Relay> get _availableRelays {
    return _allRelays.where((r) => r.status == 'available').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('internet_relays')),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar),
            onPressed: _scanNow,
            tooltip: _i18n.t('scan_local_network'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAllRelays,
            tooltip: _i18n.t('clear_all_relays'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRelays,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info Card
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _i18n.t('internet_relay_config'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _i18n.t('relay_instructions'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Selected Relay Section
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedRelays.length == 1 ? _i18n.t('selected_relay') : _i18n.t('selected_relays'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_selectedRelays.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _i18n.t('no_relays_selected'),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._selectedRelays.map((relay) {
                      final profile = _profileService.getProfile();
                      return _RelayCard(
                        relay: relay,
                        userLatitude: profile.latitude,
                        userLongitude: profile.longitude,
                        onSetPreferred: () => _setPreferred(relay),
                        onSetBackup: () => _setBackup(relay),
                        onSetAvailable: () => _setAvailable(relay),
                        onDelete: () => _deleteRelay(relay),
                        onTest: () => _testConnection(relay),
                      );
                    }),

                  const SizedBox(height: 32),

                  // Available Relays Section
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _i18n.t('available_relays'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_availableRelays.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _i18n.t('all_relays_selected'),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._availableRelays.map((relay) {
                      final profile = _profileService.getProfile();
                      return _RelayCard(
                        relay: relay,
                        userLatitude: profile.latitude,
                        userLongitude: profile.longitude,
                        onSetPreferred: () => _setPreferred(relay),
                        onSetBackup: () => _setBackup(relay),
                        onSetAvailable: null, // Already available
                        onDelete: () => _deleteRelay(relay),
                        onTest: () => _testConnection(relay),
                        isAvailableRelay: true,
                      );
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomRelay,
        icon: const Icon(Icons.add),
        label: Text(_i18n.t('add_relay')),
      ),
    );
  }
}

// Relay Card Widget
class _RelayCard extends StatelessWidget {
  final Relay relay;
  final double? userLatitude;
  final double? userLongitude;
  final VoidCallback onSetPreferred;
  final VoidCallback onSetBackup;
  final VoidCallback? onSetAvailable;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final bool isAvailableRelay;

  const _RelayCard({
    required this.relay,
    this.userLatitude,
    this.userLongitude,
    required this.onSetPreferred,
    required this.onSetBackup,
    required this.onSetAvailable,
    required this.onDelete,
    required this.onTest,
    this.isAvailableRelay = false,
  });

  I18nService get _i18n => I18nService();

  String _getStatusDisplayText() {
    switch (relay.status) {
      case 'preferred':
        return _i18n.t('preferred');
      case 'backup':
        return _i18n.t('backup');
      default:
        return _i18n.t('available');
    }
  }

  String _getConnectionStatusText() {
    if (relay.isConnected) {
      return relay.latency != null
        ? _i18n.translate('connected_with_latency', params: [relay.latency.toString()])
        : _i18n.t('connected');
    }
    return _i18n.t('disconnected');
  }

  String? _getDistanceText(double? userLat, double? userLon) {
    final distance = relay.calculateDistance(userLat, userLon);
    if (distance == null) return null;

    if (distance < 1) {
      final meters = (distance * 1000).round();
      return _i18n.translate('meters_away', params: [meters.toString()]);
    } else {
      final km = distance.round();
      return _i18n.translate('kilometers_away', params: [km.toString()]);
    }
  }

  Color _getStatusColor(BuildContext context) {
    switch (relay.status) {
      case 'preferred':
        return Colors.green;
      case 'backup':
        return Colors.orange;
      default:
        // Show green if relay is online/reachable (has device count data)
        return relay.connectedDevices != null
            ? Colors.green
            : Theme.of(context).colorScheme.outline;
    }
  }

  IconData _getStatusIcon() {
    switch (relay.status) {
      case 'preferred':
        return Icons.star;
      case 'backup':
        return Icons.check_circle;
      default:
        return Icons.cloud_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(
                  _getStatusIcon(),
                  color: _getStatusColor(context),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relay.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (relay.description != null && relay.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          relay.description!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        relay.url,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 11,
                            ),
                      ),
                      if (relay.location != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              relay.location!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            if (relay.latitude != null && relay.longitude != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '(${relay.latitude!.toStringAsFixed(4)}, ${relay.longitude!.toStringAsFixed(4)})',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      // Display distance if available
                      if (_getDistanceText(userLatitude, userLongitude) != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.straighten,
                              size: 14,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getDistanceText(userLatitude, userLongitude)!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.secondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isAvailableRelay)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(context).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getStatusColor(context),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _getStatusDisplayText(),
                      style: TextStyle(
                        color: _getStatusColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Connection Status (hide for available relays)
            if (relay.lastChecked != null && !isAvailableRelay)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          relay.isConnected ? Icons.check_circle : Icons.error,
                          size: 16,
                          color: relay.isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getConnectionStatusText(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Text(
                          _i18n.translate('last_checked', params: [_formatTime(relay.lastChecked!)]),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    // Show connected devices count if available
                    if (relay.connectedDevices != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.devices,
                            size: 14,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${relay.connectedDevices} ${relay.connectedDevices == 1 ? _i18n.t("device") : _i18n.t("devices_connected")}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Only show Set Preferred if NOT already preferred
                if (relay.status != 'preferred')
                  OutlinedButton.icon(
                    onPressed: onSetPreferred,
                    icon: const Icon(Icons.star, size: 16),
                    label: Text(_i18n.t('set_preferred')),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (relay.status != 'backup')
                  OutlinedButton.icon(
                    onPressed: onSetBackup,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(_i18n.t('set_as_backup')),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (onSetAvailable != null)
                  OutlinedButton.icon(
                    onPressed: onSetAvailable,
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: Text(_i18n.t('remove')),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onTest,
                  icon: const Icon(Icons.network_check, size: 16),
                  label: Text(_i18n.t('test')),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                  tooltip: _i18n.t('delete'),
                  color: Theme.of(context).colorScheme.error,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

// Add Relay Dialog - simplified to just IP:port input
class _AddRelayDialog extends StatefulWidget {
  const _AddRelayDialog();

  @override
  State<_AddRelayDialog> createState() => _AddRelayDialogState();
}

class _AddRelayDialogState extends State<_AddRelayDialog> {
  final _addressController = TextEditingController();
  bool _isConnecting = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final address = _addressController.text.trim();

    if (address.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an address';
        _isError = true;
      });
      return;
    }

    // Parse address - support formats: host:port, host (default port 80)
    String host;
    int port;

    // Remove any protocol prefix if user accidentally added it
    String cleanAddress = address
        .replaceAll('wss://', '')
        .replaceAll('ws://', '')
        .replaceAll('https://', '')
        .replaceAll('http://', '');

    // Remove trailing slash
    if (cleanAddress.endsWith('/')) {
      cleanAddress = cleanAddress.substring(0, cleanAddress.length - 1);
    }

    if (cleanAddress.contains(':')) {
      final parts = cleanAddress.split(':');
      host = parts[0];
      port = int.tryParse(parts[1]) ?? 80;
    } else {
      host = cleanAddress;
      port = 80;
    }

    if (host.isEmpty) {
      setState(() {
        _statusMessage = 'Invalid address format';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to $host:$port...';
      _isError = false;
    });

    try {
      // Try to fetch relay info from API first
      Map<String, dynamic>? relayInfo;
      String? workingProtocol;

      // Try HTTPS first, then HTTP
      for (final protocol in ['https', 'http']) {
        try {
          setState(() {
            _statusMessage = 'Trying $protocol://$host:$port...';
          });

          final response = await http.get(
            Uri.parse('$protocol://$host:$port/api/status'),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            if (data['service'] == 'Geogram Relay Server') {
              relayInfo = data;
              workingProtocol = protocol == 'https' ? 'wss' : 'ws';
              break;
            }
          }
        } catch (_) {
          // Try next protocol
        }
      }

      if (relayInfo == null) {
        setState(() {
          _statusMessage = 'Could not connect to relay at $host:$port';
          _isError = true;
          _isConnecting = false;
        });
        return;
      }

      // Extract relay details from API response
      final name = relayInfo['name'] as String? ??
                   relayInfo['callsign'] as String? ??
                   '$host:$port';
      final callsign = relayInfo['callsign'] as String?;
      final description = relayInfo['description'] as String?;
      final location = relayInfo['location'] as Map<String, dynamic>?;

      String? locationStr;
      double? latitude;
      double? longitude;

      if (location != null) {
        final city = location['city'] as String?;
        final country = location['country'] as String?;
        if (city != null && country != null) {
          locationStr = '$city, $country';
        } else if (city != null) {
          locationStr = city;
        } else if (country != null) {
          locationStr = country;
        }
        latitude = (location['latitude'] as num?)?.toDouble();
        longitude = (location['longitude'] as num?)?.toDouble();
      }

      setState(() {
        _statusMessage = 'Connected! Found relay: $name';
        _isError = false;
      });

      // Wait a moment to show success message
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Return the relay info
      Navigator.pop(context, {
        'name': name,
        'url': '$workingProtocol://$host:$port',
        if (callsign != null) 'callsign': callsign,
        if (locationStr != null) 'location': locationStr,
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        if (description != null) 'description': description,
      });

    } catch (e) {
      setState(() {
        _statusMessage = 'Connection failed: $e';
        _isError = true;
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Relay'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Relay Address',
                hintText: 'e.g., 127.0.0.1:8080 or relay.example.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
              autofocus: true,
              enabled: !_isConnecting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter IP:port or hostname:port',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _isError ? Icons.error : Icons.check_circle,
                      size: 16,
                      color: _isError ? Colors.red : Colors.green,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _isError ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isConnecting ? null : _connect,
          child: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}

// Network Scan Dialog
class _NetworkScanDialog extends StatefulWidget {
  final RelayService relayService;
  final I18nService i18n;

  const _NetworkScanDialog({
    required this.relayService,
    required this.i18n,
  });

  @override
  State<_NetworkScanDialog> createState() => _NetworkScanDialogState();
}

class _NetworkScanDialogState extends State<_NetworkScanDialog> {
  final RelayDiscoveryService _discoveryService = RelayDiscoveryService();
  List<NetworkScanResult> _results = [];
  String _statusMessage = 'Initializing scan...';
  int _scannedHosts = 0;
  int _totalHosts = 1;
  bool _isScanning = true;
  bool _scanComplete = false;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    final results = await _discoveryService.scanWithProgress(
      onProgress: (message, scanned, total, foundResults) {
        if (mounted) {
          setState(() {
            _statusMessage = message;
            _scannedHosts = scanned;
            _totalHosts = total > 0 ? total : 1;
            _results = List.from(foundResults);
          });
        }
      },
      shouldCancel: () => _stopRequested,
      timeoutMs: 1500, // Increased timeout for reliability
    );

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanComplete = true;
        _results = results;
      });

      // Auto-add found relays
      for (var result in results.where((r) => r.type == 'relay')) {
        await _addRelay(result);
      }
    }
  }

  void _stopScan() {
    setState(() {
      _stopRequested = true;
      _statusMessage = 'Stopping scan...';
    });
  }

  Future<void> _addRelay(NetworkScanResult result) async {
    try {
      // Build a good name: prefer callsign, then name, then description
      String relayName;
      if (result.callsign != null && result.callsign!.isNotEmpty) {
        relayName = result.callsign!;
      } else if (result.name != null && result.name!.isNotEmpty) {
        relayName = result.name!;
      } else if (result.description != null && result.description!.isNotEmpty) {
        relayName = result.description!;
      } else {
        relayName = 'Relay at ${result.ip}';
      }

      final relay = Relay(
        url: result.wsUrl,
        name: relayName,
        callsign: result.callsign,
        status: 'available',
        location: result.location,
        latitude: result.latitude,
        longitude: result.longitude,
        connectedDevices: result.connectedDevices,
      );

      final added = await widget.relayService.addRelay(relay);
      if (added) {
        LogService().log('Added relay from scan: ${relay.name}');
      }
    } catch (e) {
      LogService().log('Error adding relay from scan: $e');
    }
  }

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'relay':
        return Icons.cloud;
      case 'desktop':
        return Icons.computer;
      case 'client':
        return Icons.smartphone;
      default:
        return Icons.device_unknown;
    }
  }

  Color _getDeviceColor(String type) {
    switch (type) {
      case 'relay':
        return Colors.blue;
      case 'desktop':
        return Colors.green;
      case 'client':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _totalHosts > 0 ? _scannedHosts / _totalHosts : 0.0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.radar, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Network Scan'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress section
            if (_isScanning) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scanned $_scannedHosts of $_totalHosts hosts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Results section
            if (_results.isNotEmpty) ...[
              Text(
                'Found ${_results.length} device(s):',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: _getDeviceColor(result.type).withOpacity(0.2),
                        child: Icon(
                          _getDeviceIcon(result.type),
                          color: _getDeviceColor(result.type),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        result.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (result.description != null && result.description!.isNotEmpty)
                            Text(
                              result.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            '${result.ip}:${result.port}',
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 11,
                            ),
                          ),
                          if (result.location != null)
                            Text(
                              result.location!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 11,
                              ),
                            ),
                          if (result.connectedDevices != null)
                            Text(
                              '${result.connectedDevices} device(s) connected',
                              style: TextStyle(
                                color: theme.colorScheme.tertiary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getDeviceColor(result.type).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          result.type.toUpperCase(),
                          style: TextStyle(
                            color: _getDeviceColor(result.type),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else if (_scanComplete) ...[
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No devices found on local network',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tips:\n'
                      '  - Make sure devices are powered on\n'
                      '  - Check firewall settings\n'
                      '  - Ensure devices are on the same network',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_scanComplete && _results.where((r) => r.type == 'relay').isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Found relays have been added automatically',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isScanning) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, <NetworkScanResult>[]),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _stopRequested ? null : _stopScan,
            child: Text(_stopRequested ? 'Stopping...' : 'Stop & Use Results'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.pop(context, _results),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
