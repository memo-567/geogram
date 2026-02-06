/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/profile.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../util/nostr_key_generator.dart';
import '../util/nostr_crypto.dart';

/// Parameters for vanity key generation in isolate
class _VanityGenParams {
  final String pattern;
  final bool isStation;
  final int batchSize;
  final SendPort sendPort;

  _VanityGenParams({
    required this.pattern,
    required this.isStation,
    required this.batchSize,
    required this.sendPort,
  });
}

/// Result from vanity key generation
class _VanityGenResult {
  final int keysGenerated;
  final List<Map<String, String>> matches;

  _VanityGenResult({required this.keysGenerated, required this.matches});
}

/// Isolate entry point for vanity key generation
void _vanityGeneratorIsolate(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message == 'stop') {
      receivePort.close();
      return;
    }

    if (message is Map<String, dynamic>) {
      final pattern = message['pattern'] as String;
      final isStation = message['isStation'] as bool;
      final batchSize = message['batchSize'] as int;

      int keysGenerated = 0;
      final matches = <Map<String, String>>[];

      for (int i = 0; i < batchSize; i++) {
        final keys = NostrKeyGenerator.generateKeyPair();
        keysGenerated++;

        final callsign = isStation
            ? NostrKeyGenerator.deriveStationCallsign(keys.npub)
            : keys.callsign;

        if (callsign.contains(pattern)) {
          matches.add({
            'npub': keys.npub,
            'nsec': keys.nsec,
            'callsign': callsign,
          });
        }
      }

      mainSendPort.send({
        'keysGenerated': keysGenerated,
        'matches': matches,
      });
    }
  });
}

/// Station setup mode
enum StationSetupMode {
  createLocal,
  connectRemote,
}

/// Full-screen page for creating a new profile
class NewProfilePage extends StatefulWidget {
  const NewProfilePage({super.key});

  @override
  State<NewProfilePage> createState() => _NewProfilePageState();
}

class _VanityMatch {
  final NostrKeys keys;
  final DateTime foundAt;
  bool pinned;

  _VanityMatch({required this.keys, required this.foundAt, this.pinned = false});
}

class _NewProfilePageState extends State<NewProfilePage> {
  final I18nService _i18n = I18nService();
  final ProfileService _profileService = ProfileService();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _vanityPatternController = TextEditingController();

  // Station-specific controllers
  final TextEditingController _stationNameController = TextEditingController();
  final TextEditingController _stationDescriptionController = TextEditingController();
  final TextEditingController _remoteUrlController = TextEditingController();
  final TextEditingController _remoteNsecController = TextEditingController();

  ProfileType _selectedType = ProfileType.client;
  bool _useExtension = false;
  bool _extensionAvailable = false;
  bool _checkingExtension = true;
  bool _hasExistingStation = false;

  // Station setup mode
  StationSetupMode _stationMode = StationSetupMode.createLocal;
  int _allocatedMb = 10000;
  bool _obscureNsec = true;

  // Remote connection state
  bool _isTestingConnection = false;
  bool _connectionTested = false;
  bool _connectionSuccess = false;
  String? _testError;
  Map<String, dynamic>? _remoteStatus;

  // Pre-generated keys for callsign preview
  NostrKeys? _generatedKeys;

  // Vanity generator state
  bool _vanityRunning = false;
  int _vanityKeysGenerated = 0;
  Duration _vanityElapsedTime = Duration.zero;
  Timer? _vanityTimer;
  Stopwatch? _vanityStopwatch;
  final List<_VanityMatch> _vanityMatches = [];
  _VanityMatch? _selectedVanityMatch;

  // Isolate for vanity generation
  Isolate? _vanityIsolate;
  ReceivePort? _vanityReceivePort;
  SendPort? _vanitySendPort;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _checkExtensionAvailability();
    _checkExistingStation();
    _generateNewCallsign();
    _vanityPatternController.addListener(_onVanityPatternChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopVanityGenerator();
    _vanityPatternController.removeListener(_onVanityPatternChanged);
    _nicknameController.dispose();
    _vanityPatternController.dispose();
    _stationNameController.dispose();
    _stationDescriptionController.dispose();
    _remoteUrlController.dispose();
    _remoteNsecController.dispose();
    super.dispose();
  }

  void _onVanityPatternChanged() {
    setState(() {});
  }

  void _checkExistingStation() {
    final profiles = _profileService.getAllProfiles();
    _hasExistingStation = profiles.any((p) => p.isRelay);
  }

  void _generateNewCallsign() {
    final keys = NostrKeyGenerator.generateKeyPair();
    setState(() {
      _generatedKeys = keys;
      _selectedVanityMatch = null;
    });
  }

  String _getDisplayCallsign() {
    if (_selectedVanityMatch != null) {
      if (_selectedType == ProfileType.station) {
        return NostrKeyGenerator.deriveStationCallsign(_selectedVanityMatch!.keys.npub);
      }
      return _selectedVanityMatch!.keys.callsign;
    }
    if (_generatedKeys == null) return '------';
    if (_selectedType == ProfileType.station) {
      return NostrKeyGenerator.deriveStationCallsign(_generatedKeys!.npub);
    }
    return _generatedKeys!.callsign;
  }

  NostrKeys? _getActiveKeys() {
    return _selectedVanityMatch?.keys ?? _generatedKeys;
  }

  Future<void> _checkExtensionAvailability() async {
    if (kIsWeb) {
      final available = await _profileService.isExtensionAvailable();
      if (mounted) {
        setState(() {
          _extensionAvailable = available;
          _checkingExtension = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _extensionAvailable = false;
          _checkingExtension = false;
        });
      }
    }
  }

  Future<void> _startVanityGenerator() async {
    final pattern = _vanityPatternController.text.trim().toUpperCase();
    if (pattern.isEmpty || pattern.length > 4) return;

    setState(() {
      _vanityRunning = true;
      _vanityKeysGenerated = 0;
      _vanityMatches.clear();
      _selectedVanityMatch = null;
    });

    _vanityStopwatch = Stopwatch()..start();
    _vanityTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_disposed && mounted) {
        setState(() {
          _vanityElapsedTime = _vanityStopwatch!.elapsed;
        });
      }
    });

    // Start isolate for key generation
    _vanityReceivePort = ReceivePort();
    _vanityIsolate = await Isolate.spawn(
      _vanityGeneratorIsolate,
      _vanityReceivePort!.sendPort,
    );

    // Listen for messages from isolate
    _vanityReceivePort!.listen((message) {
      if (message is SendPort) {
        // Got the send port from isolate, start generating
        _vanitySendPort = message;
        _requestNextBatch(pattern);
      } else if (message is Map<String, dynamic>) {
        // Got results from isolate
        final keysGenerated = message['keysGenerated'] as int;
        final matches = message['matches'] as List<dynamic>;

        if (!_disposed && mounted) {
          setState(() {
            _vanityKeysGenerated += keysGenerated;

            for (final match in matches) {
              final m = match as Map<String, dynamic>;
              _vanityMatches.insert(0, _VanityMatch(
                keys: NostrKeys(
                  npub: m['npub'] as String,
                  nsec: m['nsec'] as String,
                  callsign: m['callsign'] as String,
                ),
                foundAt: DateTime.now(),
              ));
              // Keep only 500 most recent matches (but preserve pinned)
              if (_vanityMatches.length > 500) {
                // Find the last non-pinned match to remove
                for (int i = _vanityMatches.length - 1; i >= 0; i--) {
                  if (!_vanityMatches[i].pinned) {
                    _vanityMatches.removeAt(i);
                    break;
                  }
                }
              }
            }
          });
        }

        // Request next batch if still running
        if (_vanityRunning && !_disposed && mounted) {
          _requestNextBatch(pattern);
        }
      }
    });
  }

  void _requestNextBatch(String pattern) {
    _vanitySendPort?.send({
      'pattern': pattern,
      'isStation': _selectedType == ProfileType.station,
      'batchSize': 1000, // Generate 1000 keys per batch
    });
  }

  void _stopVanityGenerator() {
    _vanitySendPort?.send('stop');
    _vanityIsolate?.kill(priority: Isolate.immediate);
    _vanityIsolate = null;
    _vanityReceivePort?.close();
    _vanityReceivePort = null;
    _vanitySendPort = null;

    _vanityRunning = false;
    _vanityTimer?.cancel();
    _vanityTimer = null;
    _vanityStopwatch?.stop();

    if (!_disposed && mounted) {
      setState(() {});
    }
  }

  void _selectVanityMatch(_VanityMatch match) {
    setState(() {
      _selectedVanityMatch = match;
    });
  }

  void _togglePin(_VanityMatch match) {
    setState(() {
      match.pinned = !match.pinned;
    });
  }

  void _resetConnectionTest() {
    if (_connectionTested) {
      setState(() {
        _connectionTested = false;
        _connectionSuccess = false;
        _testError = null;
        _remoteStatus = null;
      });
    }
  }

  Future<void> _testRemoteConnection() async {
    final url = _remoteUrlController.text.trim();
    final nsec = _remoteNsecController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a station URL')),
      );
      return;
    }

    if (nsec.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the station NSEC')),
      );
      return;
    }

    if (!nsec.startsWith('nsec1')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid NSEC format. It should start with "nsec1"')),
      );
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionTested = false;
      _testError = null;
    });

    try {
      // Convert URL to HTTP if needed for status check
      var statusUrl = url;
      if (statusUrl.startsWith('wss://')) {
        statusUrl = statusUrl.replaceFirst('wss://', 'https://');
      } else if (statusUrl.startsWith('ws://')) {
        statusUrl = statusUrl.replaceFirst('ws://', 'http://');
      }
      if (!statusUrl.endsWith('/')) {
        statusUrl += '/';
      }
      statusUrl += 'api/status';

      LogService().log('Testing connection to: $statusUrl');

      final response = await http.get(
        Uri.parse(statusUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final status = json.decode(response.body) as Map<String, dynamic>;

        // Verify NSEC is valid by attempting to decode it
        try {
          final privateKeyHex = NostrCrypto.decodeNsec(nsec);
          NostrCrypto.derivePublicKey(privateKeyHex);

          if (!_disposed && mounted) {
            setState(() {
              _connectionTested = true;
              _connectionSuccess = true;
              _remoteStatus = status;
            });
          }
        } catch (e) {
          if (!_disposed && mounted) {
            setState(() {
              _connectionTested = true;
              _connectionSuccess = false;
              _testError = 'Invalid NSEC: $e';
            });
          }
        }
      } else {
        if (!_disposed && mounted) {
          setState(() {
            _connectionTested = true;
            _connectionSuccess = false;
            _testError = 'Server returned status ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      LogService().log('Connection test failed: $e');
      if (!_disposed && mounted) {
        setState(() {
          _connectionTested = true;
          _connectionSuccess = false;
          _testError = e.toString();
        });
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  bool _canCreate() {
    if (_selectedType == ProfileType.client) {
      return _getActiveKeys() != null || _useExtension;
    } else {
      // Station profile
      if (_stationMode == StationSetupMode.createLocal) {
        return _getActiveKeys() != null && _stationNameController.text.trim().isNotEmpty;
      } else {
        // Connect remote
        return _connectionSuccess && _remoteStatus != null;
      }
    }
  }

  void _create() {
    if (!_canCreate()) return;

    if (_selectedType == ProfileType.client) {
      final activeKeys = _getActiveKeys();
      Navigator.pop(context, {
        'type': _selectedType,
        'useExtension': _useExtension,
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        if (!_useExtension && activeKeys != null) ...{
          'npub': activeKeys.npub,
          'nsec': activeKeys.nsec,
          'callsign': _getDisplayCallsign(),
        },
      });
    } else {
      // Station profile
      if (_stationMode == StationSetupMode.createLocal) {
        final activeKeys = _getActiveKeys();
        Navigator.pop(context, {
          'type': _selectedType,
          'stationMode': 'local',
          'stationName': _stationNameController.text.trim(),
          'stationDescription': _stationDescriptionController.text.trim(),
          'allocatedMb': _allocatedMb,
          'npub': activeKeys!.npub,
          'nsec': activeKeys.nsec,
          'callsign': _getDisplayCallsign(),
        });
      } else {
        // Connect remote - derive keys from the remote's nsec
        final nsec = _remoteNsecController.text.trim();
        final privateKeyHex = NostrCrypto.decodeNsec(nsec);
        final publicKeyHex = NostrCrypto.derivePublicKey(privateKeyHex);
        final npub = NostrCrypto.encodeNpub(publicKeyHex);
        final callsign = NostrKeyGenerator.deriveStationCallsign(npub);

        Navigator.pop(context, {
          'type': _selectedType,
          'stationMode': 'remote',
          'remoteUrl': _remoteUrlController.text.trim(),
          'remoteNsec': nsec,
          'remoteStatus': _remoteStatus,
          'npub': npub,
          'nsec': nsec,
          'callsign': callsign,
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}.${tenths}s';
  }

  String _formatStorage(int mb) {
    if (mb >= 1000) {
      return '${(mb / 1000).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('create_profile')),
        actions: [
          FilledButton.icon(
            onPressed: _canCreate() ? _create : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(_i18n.t('create')),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.onPrimary,
              foregroundColor: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // NIP-07 Extension option (web only)
          if (kIsWeb) ...[
            _buildExtensionOption(theme),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
          ],

          // Profile type selection (only show if not using extension)
          if (!_useExtension) ...[
            Text(
              _i18n.t('profile_type'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTypeOption(
                    theme: theme,
                    type: ProfileType.client,
                    icon: Icons.person,
                    title: _i18n.t('client'),
                    description: _i18n.t('client_description'),
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTypeOption(
                    theme: theme,
                    type: ProfileType.station,
                    icon: Icons.cell_tower,
                    title: _i18n.t('station'),
                    description: _i18n.t('station_description'),
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Show different content based on profile type
            if (_selectedType == ProfileType.client)
              _buildClientOptions(theme)
            else
              _buildStationOptions(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildClientOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Callsign preview with regenerate button
        Text(
          _i18n.t('your_callsign'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _getDisplayCallsign(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _selectedVanityMatch != null
                        ? Colors.green
                        : theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _vanityRunning ? null : _generateNewCallsign,
                icon: const Icon(Icons.refresh),
                tooltip: _i18n.t('generate_new'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Nickname field
        Text(
          _i18n.t('nickname_optional'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nicknameController,
          decoration: InputDecoration(
            hintText: _i18n.t('enter_nickname'),
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        const SizedBox(height: 32),

        // Vanity Generator Section
        _buildVanityGenerator(theme),
      ],
    );
  }

  Widget _buildStationOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Station mode selection
        Text(
          'Station Setup',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStationModeOption(
                theme: theme,
                mode: StationSetupMode.createLocal,
                icon: Icons.hub,
                title: 'Create Local',
                description: 'Run station on this device',
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStationModeOption(
                theme: theme,
                mode: StationSetupMode.connectRemote,
                icon: Icons.cloud,
                title: 'Connect Remote',
                description: 'Manage a remote station',
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (_stationMode == StationSetupMode.createLocal)
          _buildLocalStationOptions(theme)
        else
          _buildRemoteStationOptions(theme),
      ],
    );
  }

  Widget _buildStationModeOption({
    required ThemeData theme,
    required StationSetupMode mode,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    final isSelected = _stationMode == mode;

    return InkWell(
      onTap: () => setState(() {
        _stationMode = mode;
        _resetConnectionTest();
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? color.withOpacity(0.1) : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? color : Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected ? color : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalStationOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Station name
        Text(
          'Station Name *',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _stationNameController,
          decoration: const InputDecoration(
            hintText: 'e.g., My Community Station',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),

        // Description
        Text(
          'Description (optional)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _stationDescriptionController,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Describe your station...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),

        // Storage allocation
        Text(
          'Storage Allocation',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text('Disk space for cached data')),
                  const SizedBox(width: 8),
                  Text(
                    _formatStorage(_allocatedMb),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: _allocatedMb.toDouble(),
                min: 500,
                max: 50000,
                divisions: 99,
                label: _formatStorage(_allocatedMb),
                onChanged: (value) {
                  setState(() => _allocatedMb = value.round());
                },
              ),
              Text(
                'This space will be used to cache messages and media',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Callsign preview
        Text(
          'Station Callsign',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _getDisplayCallsign(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _selectedVanityMatch != null
                        ? Colors.green
                        : Colors.orange,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _vanityRunning ? null : _generateNewCallsign,
                icon: const Icon(Icons.refresh),
                tooltip: 'Generate new',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Station callsigns start with X3',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),

        // Vanity generator
        _buildVanityGenerator(theme),
      ],
    );
  }

  Widget _buildRemoteStationOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[400], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Connect to a station server running on another device. '
                  'You\'ll need the station URL and its NSEC (private key).',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // URL field
        Text(
          'Station URL',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _remoteUrlController,
          decoration: const InputDecoration(
            hintText: 'https://station.example.com',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          onChanged: (_) => _resetConnectionTest(),
        ),
        const SizedBox(height: 16),

        // NSEC field
        Text(
          'Station NSEC',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _remoteNsecController,
          obscureText: _obscureNsec,
          decoration: InputDecoration(
            hintText: 'nsec1...',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_obscureNsec ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureNsec = !_obscureNsec),
            ),
          ),
          onChanged: (_) => _resetConnectionTest(),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[400], size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Keep your NSEC private. It grants full control over the station.',
                  style: TextStyle(fontSize: 11, color: Colors.orange[300]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Test connection button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isTestingConnection ? null : _testRemoteConnection,
            icon: _isTestingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
          ),
        ),

        // Connection status
        if (_connectionTested) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _connectionSuccess
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _connectionSuccess ? Colors.green : Colors.red,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _connectionSuccess ? Icons.check_circle : Icons.error,
                      color: _connectionSuccess ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _connectionSuccess ? 'Connection successful!' : 'Connection failed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _connectionSuccess ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                if (_connectionSuccess && _remoteStatus != null) ...[
                  const SizedBox(height: 8),
                  Text('Name: ${_remoteStatus!['name'] ?? 'Unknown'}'),
                  Text('Callsign: ${_remoteStatus!['callsign'] ?? 'Unknown'}'),
                ],
                if (!_connectionSuccess && _testError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testError!,
                    style: TextStyle(color: Colors.red[300], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVanityGenerator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                _i18n.t('vanity_generator'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _i18n.t('vanity_generator_description'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Pattern input and controls
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vanityPatternController,
                  decoration: InputDecoration(
                    labelText: _i18n.t('pattern'),
                    hintText: 'ABCD',
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                  maxLength: 4,
                  textCapitalization: TextCapitalization.characters,
                  enabled: !_vanityRunning,
                ),
              ),
              const SizedBox(width: 12),
              if (_vanityRunning)
                FilledButton.tonalIcon(
                  onPressed: _stopVanityGenerator,
                  icon: const Icon(Icons.pause),
                  label: Text(_i18n.t('pause')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.withOpacity(0.2),
                    foregroundColor: Colors.orange,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _vanityPatternController.text.trim().isNotEmpty
                      ? _startVanityGenerator
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_i18n.t('start')),
                ),
            ],
          ),

          // Progress display
          if (_vanityKeysGenerated > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_vanityRunning) ...[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_i18n.t('keys_generated')}: ${_vanityKeysGenerated.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_i18n.t('elapsed_time')}: ${_formatDuration(_vanityElapsedTime)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_i18n.t('matches')}: ${_vanityMatches.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _vanityMatches.isNotEmpty ? Colors.green : null,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Matches list
          if (_vanityMatches.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  _i18n.t('recent_matches'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_vanityMatches.length})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Builder(
                builder: (context) {
                  // Sort matches: pinned first, then by time
                  final sortedMatches = List<_VanityMatch>.from(_vanityMatches)
                    ..sort((a, b) {
                      if (a.pinned && !b.pinned) return -1;
                      if (!a.pinned && b.pinned) return 1;
                      return b.foundAt.compareTo(a.foundAt);
                    });
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: sortedMatches.length,
                    itemBuilder: (context, index) {
                      final match = sortedMatches[index];
                      final isSelected = _selectedVanityMatch == match;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSelected
                            ? theme.colorScheme.primaryContainer
                            : match.pinned
                                ? theme.colorScheme.tertiaryContainer.withOpacity(0.5)
                                : null,
                        child: InkWell(
                          onTap: () => _selectVanityMatch(match),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: theme.colorScheme.primary,
                                    size: 20,
                                  )
                                else
                                  Icon(
                                    Icons.radio_button_unchecked,
                                    color: theme.colorScheme.outline,
                                    size: 20,
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedType == ProfileType.station
                                            ? NostrKeyGenerator.deriveStationCallsign(match.keys.npub)
                                            : match.keys.callsign,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          color: isSelected
                                              ? theme.colorScheme.onPrimaryContainer
                                              : null,
                                        ),
                                      ),
                                      Text(
                                        '${match.keys.npub.substring(0, 20)}...',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isSelected
                                              ? theme.colorScheme.onPrimaryContainer.withOpacity(0.7)
                                              : theme.colorScheme.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _togglePin(match),
                                  icon: Icon(
                                    match.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                    size: 20,
                                    color: match.pinned
                                        ? theme.colorScheme.tertiary
                                        : theme.colorScheme.outline,
                                  ),
                                  tooltip: match.pinned ? 'Unpin' : 'Pin',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtensionOption(ThemeData theme) {
    final isSelected = _useExtension;

    return InkWell(
      onTap: _extensionAvailable
          ? () => setState(() {
                _useExtension = !_useExtension;
              })
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Colors.purple
                : _extensionAvailable
                    ? Colors.grey[300]!
                    : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Colors.purple.withOpacity(0.1)
              : _extensionAvailable
                  ? null
                  : Colors.grey[100],
        ),
        child: Row(
          children: [
            Icon(
              Icons.extension,
              size: 40,
              color: _extensionAvailable
                  ? (isSelected ? Colors.purple : Colors.grey[600])
                  : Colors.grey[400],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _i18n.t('login_with_extension'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _extensionAvailable
                              ? (isSelected ? Colors.purple : null)
                              : Colors.grey[500],
                        ),
                      ),
                      if (_checkingExtension) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ] else if (_extensionAvailable) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _i18n.t('available'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _extensionAvailable
                        ? _i18n.t('extension_login_description')
                        : _i18n.t('extension_not_available'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (_extensionAvailable)
              Checkbox(
                value: _useExtension,
                onChanged: (value) {
                  setState(() {
                    _useExtension = value ?? false;
                  });
                },
                activeColor: Colors.purple,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeOption({
    required ThemeData theme,
    required ProfileType type,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    final isSelected = _selectedType == type && !_useExtension;
    final isDisabled = _useExtension || (type == ProfileType.station && _hasExistingStation);

    return InkWell(
      onTap: isDisabled
          ? null
          : () {
              setState(() {
                _selectedType = type;
                // Reset vanity matches when switching types
                _vanityMatches.clear();
                _selectedVanityMatch = null;
                _generateNewCallsign();
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? color
                : isDisabled
                    ? Colors.grey[200]!
                    : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? color.withOpacity(0.1)
              : isDisabled
                  ? Colors.grey[100]
                  : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isDisabled
                  ? Colors.grey[400]
                  : (isSelected ? color : Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDisabled ? Colors.grey[400] : (isSelected ? color : null),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              type == ProfileType.station && _hasExistingStation
                  ? _i18n.t('station_already_exists')
                  : description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDisabled ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
