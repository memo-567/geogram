import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/log_service.dart';
import '../services/config_service.dart';
import '../services/profile_service.dart';
import '../services/callsign_generator.dart';
import '../version.dart';

/// Relay server settings
class RelayServerSettings {
  int port;
  bool enabled;
  bool tileServerEnabled;
  bool osmFallbackEnabled;
  int maxZoomLevel;
  int maxCacheSize; // in MB
  String? description;
  String? location;
  double? latitude;
  double? longitude;

  RelayServerSettings({
    this.port = 8080,
    this.enabled = false,
    this.tileServerEnabled = true,
    this.osmFallbackEnabled = true,
    this.maxZoomLevel = 15,
    this.maxCacheSize = 500,
    this.description,
    this.location,
    this.latitude,
    this.longitude,
  });

  factory RelayServerSettings.fromJson(Map<String, dynamic> json) {
    return RelayServerSettings(
      port: json['port'] as int? ?? 8080,
      enabled: json['enabled'] as bool? ?? false,
      tileServerEnabled: json['tileServerEnabled'] as bool? ?? true,
      osmFallbackEnabled: json['osmFallbackEnabled'] as bool? ?? true,
      maxZoomLevel: json['maxZoomLevel'] as int? ?? 15,
      maxCacheSize: json['maxCacheSize'] as int? ?? 500,
      description: json['description'] as String?,
      location: json['location'] as String?,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
    );
  }

  Map<String, dynamic> toJson() => {
        'port': port,
        'enabled': enabled,
        'tileServerEnabled': tileServerEnabled,
        'osmFallbackEnabled': osmFallbackEnabled,
        'maxZoomLevel': maxZoomLevel,
        'maxCacheSize': maxCacheSize,
        'description': description,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
      };

  RelayServerSettings copyWith({
    int? port,
    bool? enabled,
    bool? tileServerEnabled,
    bool? osmFallbackEnabled,
    int? maxZoomLevel,
    int? maxCacheSize,
    String? description,
    String? location,
    double? latitude,
    double? longitude,
  }) {
    return RelayServerSettings(
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
      tileServerEnabled: tileServerEnabled ?? this.tileServerEnabled,
      osmFallbackEnabled: osmFallbackEnabled ?? this.osmFallbackEnabled,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      description: description ?? this.description,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

/// Connected WebSocket client
class ConnectedClient {
  final WebSocket socket;
  final String id;
  String? callsign;
  DateTime connectedAt;
  DateTime lastActivity;

  ConnectedClient({
    required this.socket,
    required this.id,
    this.callsign,
  })  : connectedAt = DateTime.now(),
        lastActivity = DateTime.now();
}

/// Tile cache for relay server
class TileCache {
  final Map<String, Uint8List> _cache = {};
  final Map<String, DateTime> _timestamps = {};
  int _currentSize = 0;
  final int maxSizeBytes;

  TileCache({int maxSizeMB = 500}) : maxSizeBytes = maxSizeMB * 1024 * 1024;

  Uint8List? get(String key) {
    final data = _cache[key];
    if (data != null) {
      _timestamps[key] = DateTime.now();
    }
    return data;
  }

  void put(String key, Uint8List data) {
    // Remove if already exists
    if (_cache.containsKey(key)) {
      _currentSize -= _cache[key]!.length;
    }

    // Evict old entries if needed
    while (_currentSize + data.length > maxSizeBytes && _cache.isNotEmpty) {
      _evictOldest();
    }

    _cache[key] = data;
    _timestamps[key] = DateTime.now();
    _currentSize += data.length;
  }

  void _evictOldest() {
    if (_timestamps.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _timestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestTime = entry.value;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null && _cache.containsKey(oldestKey)) {
      _currentSize -= _cache[oldestKey]!.length;
      _cache.remove(oldestKey);
      _timestamps.remove(oldestKey);
    }
  }

  int get size => _cache.length;
  int get sizeBytes => _currentSize;

  void clear() {
    _cache.clear();
    _timestamps.clear();
    _currentSize = 0;
  }

  static bool isValidImageData(Uint8List data) {
    if (data.length < 8) return false;
    // Check PNG signature
    return data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47;
  }
}

/// Relay server service for CLI mode
class RelayServerService {
  static final RelayServerService _instance = RelayServerService._internal();
  factory RelayServerService() => _instance;
  RelayServerService._internal();

  HttpServer? _httpServer;
  RelayServerSettings _settings = RelayServerSettings();
  final Map<String, ConnectedClient> _clients = {};
  final TileCache _tileCache = TileCache();
  bool _running = false;
  DateTime? _startTime;
  String? _tilesDirectory;

  bool get isRunning => _running;
  int get connectedDevices => _clients.length;
  RelayServerSettings get settings => _settings;
  DateTime? get startTime => _startTime;

  /// Initialize relay server service
  Future<void> initialize() async {
    await _loadSettings();

    // Create tiles directory
    final appDir = await getApplicationSupportDirectory();
    _tilesDirectory = '${appDir.path}/tiles';
    await Directory(_tilesDirectory!).create(recursive: true);

    LogService().log('RelayServerService initialized');
  }

  /// Load settings from config
  Future<void> _loadSettings() async {
    final config = ConfigService().getAll();
    if (config.containsKey('relayServer')) {
      _settings = RelayServerSettings.fromJson(
          config['relayServer'] as Map<String, dynamic>);
    }
  }

  /// Save settings to config
  void _saveSettings() {
    ConfigService().set('relayServer', _settings.toJson());
  }

  /// Update settings
  Future<void> updateSettings(RelayServerSettings settings) async {
    final wasRunning = _running;
    final oldPort = _settings.port;

    _settings = settings;
    _saveSettings();

    // Restart if port changed and was running
    if (wasRunning && oldPort != settings.port) {
      await stop();
      await start();
    }
  }

  /// Start the relay server
  Future<bool> start() async {
    if (_running) {
      LogService().log('Relay server already running');
      return true;
    }

    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _settings.port,
        shared: true,
      );

      _running = true;
      _startTime = DateTime.now();

      LogService().log('Relay server started on port ${_settings.port}');

      // Handle incoming connections
      _httpServer!.listen(_handleRequest, onError: (error) {
        LogService().log('Server error: $error');
      });

      return true;
    } catch (e) {
      LogService().log('Failed to start relay server: $e');
      return false;
    }
  }

  /// Stop the relay server
  Future<void> stop() async {
    if (!_running) return;

    // Close all WebSocket connections
    for (final client in _clients.values) {
      await client.socket.close();
    }
    _clients.clear();

    // Close HTTP server
    await _httpServer?.close(force: true);
    _httpServer = null;
    _running = false;
    _startTime = null;

    LogService().log('Relay server stopped');
  }

  /// Handle incoming HTTP request
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    try {
      // WebSocket upgrade
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _handleWebSocket(request);
        return;
      }

      // CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

      if (method == 'OPTIONS') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }

      // Route requests
      if (path == '/api/status' || path == '/status') {
        await _handleStatus(request);
      } else if (path == '/api/chat/rooms') {
        await _handleChatRooms(request);
      } else if (path.startsWith('/api/chat/rooms/') && path.endsWith('/messages')) {
        await _handleRoomMessages(request);
      } else if (path.startsWith('/tiles/')) {
        await _handleTileRequest(request);
      } else if (path == '/') {
        await _handleRoot(request);
      } else {
        request.response.statusCode = 404;
        request.response.write('Not Found');
      }
    } catch (e) {
      LogService().log('Request error: $e');
      request.response.statusCode = 500;
      request.response.write('Internal Server Error');
    }

    await request.response.close();
  }

  /// Handle WebSocket connection
  Future<void> _handleWebSocket(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final clientId = DateTime.now().millisecondsSinceEpoch.toString();
      final client = ConnectedClient(socket: socket, id: clientId);

      _clients[clientId] = client;
      LogService().log('WebSocket client connected: $clientId');

      socket.listen(
        (data) => _handleWebSocketMessage(client, data),
        onDone: () {
          _clients.remove(clientId);
          LogService().log('WebSocket client disconnected: $clientId');
        },
        onError: (error) {
          LogService().log('WebSocket error: $error');
          _clients.remove(clientId);
        },
      );
    } catch (e) {
      LogService().log('WebSocket upgrade failed: $e');
    }
  }

  /// Handle WebSocket message
  void _handleWebSocketMessage(ConnectedClient client, dynamic data) {
    try {
      client.lastActivity = DateTime.now();

      if (data is String) {
        final message = jsonDecode(data) as Map<String, dynamic>;
        final type = message['type'] as String?;

        if (type == 'hello') {
          // Client hello handshake
          final callsign = message['callsign'] as String?;
          client.callsign = callsign;

          // Send hello response
          final response = {
            'type': 'hello_response',
            'server': 'geogram-desktop-relay',
            'version': appVersion,
            'callsign': ProfileService().getProfile().callsign,
          };
          client.socket.add(jsonEncode(response));
          LogService().log('Hello from client: $callsign');
        }
      }
    } catch (e) {
      LogService().log('WebSocket message error: $e');
    }
  }

  /// Handle /api/status endpoint
  Future<void> _handleStatus(HttpRequest request) async {
    final profile = ProfileService().getProfile();
    final isRelay = CallsignGenerator.isRelayCallsign(profile.callsign);

    final uptime = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    final status = {
      'name': 'Geogram Desktop Relay',
      'version': appVersion,
      'callsign': profile.callsign,
      'description': _settings.description ?? 'Geogram Desktop Relay Server',
      'connected_devices': _clients.length,
      'uptime': uptime,
      'relay_mode': isRelay,
      'location': _settings.location,
      'latitude': _settings.latitude,
      'longitude': _settings.longitude,
      'tile_server': _settings.tileServerEnabled,
      'osm_fallback': _settings.osmFallbackEnabled,
      'cache_size': _tileCache.size,
      'cache_size_bytes': _tileCache.sizeBytes,
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(status));
  }

  /// Handle / root endpoint
  Future<void> _handleRoot(HttpRequest request) async {
    final profile = ProfileService().getProfile();

    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <title>Geogram Desktop Relay</title>
  <style>
    body { font-family: sans-serif; padding: 20px; max-width: 800px; margin: 0 auto; }
    h1 { color: #333; }
    .info { background: #f5f5f5; padding: 15px; border-radius: 5px; }
    .info p { margin: 5px 0; }
  </style>
</head>
<body>
  <h1>Geogram Desktop Relay</h1>
  <div class="info">
    <p><strong>Version:</strong> $appVersion</p>
    <p><strong>Callsign:</strong> ${profile.callsign}</p>
    <p><strong>Connected Devices:</strong> ${_clients.length}</p>
    <p><strong>Status:</strong> Running</p>
  </div>
  <p>API endpoint: <a href="/api/status">/api/status</a></p>
</body>
</html>
''');
  }

  /// Handle /api/chat/rooms endpoint
  Future<void> _handleChatRooms(HttpRequest request) async {
    final profile = ProfileService().getProfile();

    final response = {
      'relay': profile.callsign,
      'rooms': [
        {
          'id': 'general',
          'name': 'General',
          'description': 'General discussion',
          'member_count': _clients.length,
          'is_public': true,
        }
      ],
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
  }

  /// Handle /api/chat/rooms/{roomId}/messages endpoint
  Future<void> _handleRoomMessages(HttpRequest request) async {
    final path = request.uri.path;
    // Extract room ID from path
    final parts = path.split('/');
    final roomId = parts.length > 4 ? parts[4] : 'general';

    if (request.method == 'GET') {
      // Return empty messages for now
      final response = {
        'room': roomId,
        'messages': <Map<String, dynamic>>[],
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
    } else if (request.method == 'POST') {
      // Handle message posting
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
    }
  }

  /// Handle /tiles/{callsign}/{z}/{x}/{y}.png endpoint
  Future<void> _handleTileRequest(HttpRequest request) async {
    if (!_settings.tileServerEnabled) {
      request.response.statusCode = 404;
      request.response.write('Tile server disabled');
      return;
    }

    final path = request.uri.path;
    // Parse: /tiles/{callsign}/{z}/{x}/{y}.png
    final regex = RegExp(r'/tiles/([^/]+)/(\d+)/(\d+)/(\d+)\.png');
    final match = regex.firstMatch(path);

    if (match == null) {
      request.response.statusCode = 400;
      request.response.write('Invalid tile path');
      return;
    }

    final callsign = match.group(1)!;
    final z = int.parse(match.group(2)!);
    final x = int.parse(match.group(3)!);
    final y = int.parse(match.group(4)!);

    final layer = request.uri.queryParameters['layer'] ?? 'standard';
    final isSatellite = layer.toLowerCase() == 'satellite';

    // Validate zoom level
    if (z < 0 || z > 18) {
      request.response.statusCode = 400;
      request.response.write('Invalid zoom level');
      return;
    }

    // Check cache
    final cacheKey = '$layer/$z/$x/$y';
    var tileData = _tileCache.get(cacheKey);

    if (tileData != null) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(tileData);
      return;
    }

    // Try to load from disk cache
    final diskPath = '$_tilesDirectory/$layer/$z/$x/$y.png';
    final diskFile = File(diskPath);
    if (await diskFile.exists()) {
      tileData = await diskFile.readAsBytes();
      _tileCache.put(cacheKey, tileData);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(tileData);
      return;
    }

    // Fetch from internet if OSM fallback is enabled
    if (_settings.osmFallbackEnabled) {
      tileData = await _fetchTileFromInternet(z, x, y, isSatellite);

      if (tileData != null) {
        // Cache in memory
        if (z <= _settings.maxZoomLevel) {
          _tileCache.put(cacheKey, tileData);
        }

        // Cache to disk
        await _saveTileToDisk(diskPath, tileData);

        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(tileData);
        return;
      }
    }

    request.response.statusCode = 404;
    request.response.write('Tile not found');
  }

  /// Fetch tile from internet (OSM or Esri)
  Future<Uint8List?> _fetchTileFromInternet(int z, int x, int y, bool satellite) async {
    try {
      final url = satellite
          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x'
          : 'https://tile.openstreetmap.org/$z/$x/$y.png';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Geogram-Desktop-Relay/$appVersion',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = Uint8List.fromList(response.bodyBytes);
        if (TileCache.isValidImageData(data)) {
          return data;
        }
      }
    } catch (e) {
      LogService().log('Failed to fetch tile: $e');
    }
    return null;
  }

  /// Save tile to disk cache
  Future<void> _saveTileToDisk(String path, Uint8List data) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data);
    } catch (e) {
      LogService().log('Failed to save tile to disk: $e');
    }
  }

  /// Get server status
  Map<String, dynamic> getStatus() {
    final profile = ProfileService().getProfile();
    final uptime = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    return {
      'running': _running,
      'port': _settings.port,
      'callsign': profile.callsign,
      'connected_devices': _clients.length,
      'uptime': uptime,
      'cache_size': _tileCache.size,
      'cache_size_mb': (_tileCache.sizeBytes / (1024 * 1024)).toStringAsFixed(2),
    };
  }

  /// Clear tile cache
  void clearCache() {
    _tileCache.clear();
    LogService().log('Tile cache cleared');
  }
}
