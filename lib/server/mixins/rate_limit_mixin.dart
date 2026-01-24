// Rate limiting and IP security mixin for station server
import 'dart:io';

/// Rate limiting tracking per IP address
class IpRateLimit {
  int activeConnections = 0;
  final List<DateTime> requestTimestamps = [];
  int banCount = 0;

  /// Check if this IP has exceeded the request rate limit
  bool isRateLimited(int maxRequestsPerMinute) {
    final now = DateTime.now();
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
    requestTimestamps.removeWhere((t) => t.isBefore(oneMinuteAgo));
    return requestTimestamps.length >= maxRequestsPerMinute;
  }

  /// Record a new request from this IP
  void recordRequest() {
    requestTimestamps.add(DateTime.now());
  }

  /// Get ban duration with exponential backoff
  /// 5min -> 15min -> 1hr -> 24hr
  Duration getBanDuration(Duration baseDuration) {
    final multipliers = [1, 3, 12, 288];
    final idx = banCount.clamp(0, multipliers.length - 1);
    return baseDuration * multipliers[idx];
  }
}

/// Mixin providing rate limiting and IP banning functionality
mixin RateLimitMixin {
  // Rate limiting state
  final Map<String, IpRateLimit> rateLimitState = {};
  final Set<String> bannedIps = {};
  final Map<String, DateTime> banExpiry = {};
  Set<String> permanentBlacklist = {};
  Set<String> whitelist = {};

  // Configuration constants
  static const int maxConnectionsPerIp = 100;
  static const int maxRequestsPerMinute = 1000;
  static const Duration baseBanDuration = Duration(minutes: 5);

  // Abstract method to be implemented by the using class
  void log(String level, String message);
  String? get dataDir;

  /// Check if an IP address is currently banned
  bool isIpBanned(String ip) {
    // Check permanent blacklist first
    if (permanentBlacklist.contains(ip)) {
      return true;
    }

    // Check temporary ban
    if (bannedIps.contains(ip)) {
      final expiry = banExpiry[ip];
      if (expiry != null && DateTime.now().isBefore(expiry)) {
        return true;
      }
      // Ban expired, remove it
      bannedIps.remove(ip);
      banExpiry.remove(ip);
    }
    return false;
  }

  /// Check rate limit for an IP and record the request
  /// Returns true if request is allowed, false if rate limited
  bool checkRateLimit(String ip) {
    // Whitelisted IPs bypass rate limiting
    if (whitelist.contains(ip) || ip == '127.0.0.1' || ip == '::1') {
      return true;
    }

    final rateLimit = rateLimitState.putIfAbsent(ip, () => IpRateLimit());
    rateLimit.recordRequest();

    // Check if rate limited
    if (rateLimit.isRateLimited(maxRequestsPerMinute)) {
      return false;
    }

    // Check concurrent connections
    if (rateLimit.activeConnections >= maxConnectionsPerIp) {
      return false;
    }

    return true;
  }

  /// Ban an IP address temporarily
  void banIp(String ip) {
    final rateLimit = rateLimitState.putIfAbsent(ip, () => IpRateLimit());
    final banDuration = rateLimit.getBanDuration(baseBanDuration);
    rateLimit.banCount++;

    bannedIps.add(ip);
    banExpiry[ip] = DateTime.now().add(banDuration);
    log('WARN', 'Banned IP $ip for ${banDuration.inMinutes} minutes (ban #${rateLimit.banCount})');
  }

  /// Increment active connection count for an IP
  void incrementConnection(String ip) {
    final rateLimit = rateLimitState.putIfAbsent(ip, () => IpRateLimit());
    rateLimit.activeConnections++;
  }

  /// Decrement active connection count for an IP
  void decrementConnection(String ip) {
    final rateLimit = rateLimitState[ip];
    if (rateLimit != null && rateLimit.activeConnections > 0) {
      rateLimit.activeConnections--;
    }
  }

  /// Cleanup expired bans and stale rate limit entries
  void cleanupExpiredBans() {
    final now = DateTime.now();

    // Remove expired temporary bans
    final expiredIps = <String>[];
    for (final entry in banExpiry.entries) {
      if (now.isAfter(entry.value)) {
        expiredIps.add(entry.key);
      }
    }
    for (final ip in expiredIps) {
      bannedIps.remove(ip);
      banExpiry.remove(ip);
    }

    // Remove stale rate limit entries (no activity in last 10 minutes)
    final staleThreshold = now.subtract(const Duration(minutes: 10));
    final staleIps = <String>[];
    for (final entry in rateLimitState.entries) {
      final rateLimit = entry.value;
      if (rateLimit.activeConnections == 0 &&
          (rateLimit.requestTimestamps.isEmpty ||
              rateLimit.requestTimestamps.last.isBefore(staleThreshold))) {
        staleIps.add(entry.key);
      }
    }
    for (final ip in staleIps) {
      rateLimitState.remove(ip);
    }
  }

  /// Load security lists (blacklist/whitelist) from files
  Future<void> loadSecurityLists() async {
    final dir = dataDir;
    if (dir == null) return;

    final securityDir = Directory('$dir/security');
    if (!await securityDir.exists()) {
      await securityDir.create(recursive: true);
    }

    // Load blacklist
    final blacklistFile = File('${securityDir.path}/blacklist.txt');
    if (await blacklistFile.exists()) {
      try {
        final lines = await blacklistFile.readAsLines();
        permanentBlacklist = lines
            .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
            .map((l) => l.trim())
            .toSet();
        log('INFO', 'Loaded ${permanentBlacklist.length} blacklisted IPs');
      } catch (e) {
        log('ERROR', 'Failed to load blacklist: $e');
      }
    }

    // Load whitelist
    final whitelistFile = File('${securityDir.path}/whitelist.txt');
    if (await whitelistFile.exists()) {
      try {
        final lines = await whitelistFile.readAsLines();
        whitelist = lines
            .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
            .map((l) => l.trim())
            .toSet();
        log('INFO', 'Loaded ${whitelist.length} whitelisted IPs');
      } catch (e) {
        log('ERROR', 'Failed to load whitelist: $e');
      }
    }
  }

  /// Add an IP to the permanent blacklist
  Future<void> addToBlacklist(String ip) async {
    permanentBlacklist.add(ip);
    await _saveSecurityList('blacklist.txt', permanentBlacklist);
    log('INFO', 'Added $ip to blacklist');
  }

  /// Remove an IP from the permanent blacklist
  Future<void> removeFromBlacklist(String ip) async {
    permanentBlacklist.remove(ip);
    await _saveSecurityList('blacklist.txt', permanentBlacklist);
    log('INFO', 'Removed $ip from blacklist');
  }

  /// Add an IP to the whitelist
  Future<void> addToWhitelist(String ip) async {
    whitelist.add(ip);
    await _saveSecurityList('whitelist.txt', whitelist);
    log('INFO', 'Added $ip to whitelist');
  }

  /// Remove an IP from the whitelist
  Future<void> removeFromWhitelist(String ip) async {
    whitelist.remove(ip);
    await _saveSecurityList('whitelist.txt', whitelist);
    log('INFO', 'Removed $ip from whitelist');
  }

  Future<void> _saveSecurityList(String filename, Set<String> list) async {
    final dir = dataDir;
    if (dir == null) return;

    final file = File('$dir/security/$filename');
    await file.parent.create(recursive: true);
    await file.writeAsString(list.join('\n'));
  }

  /// Unban an IP address
  void unbanIp(String ip) {
    bannedIps.remove(ip);
    banExpiry.remove(ip);
    log('INFO', 'Unbanned IP $ip');
  }

  /// Get list of currently banned IPs with expiry times
  List<Map<String, dynamic>> getBannedIps() {
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];

    for (final ip in bannedIps) {
      final expiry = banExpiry[ip];
      if (expiry != null && now.isBefore(expiry)) {
        result.add({
          'ip': ip,
          'expiry': expiry.toIso8601String(),
          'remaining_seconds': expiry.difference(now).inSeconds,
        });
      }
    }

    return result;
  }
}
