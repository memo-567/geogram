/// High-level NNTP client.
library;

import 'dart:async';

import '../exceptions.dart';
import '../models/article.dart';
import '../models/newsgroup.dart';
import '../models/overview.dart';
import '../models/range.dart';
import 'nntp_connection.dart';
import 'nntp_response.dart';

/// High-level NNTP client for interacting with Usenet servers.
class NNTPClient {
  /// The underlying connection.
  final NNTPConnection _connection;

  /// Server capabilities (populated after connect).
  final Set<String> _capabilities = {};

  /// Whether connected.
  bool get isConnected => _connection.isConnected;

  /// Whether posting is allowed.
  bool get postingAllowed => _connection.postingAllowed;

  /// Currently selected group.
  String? get selectedGroup => _connection.selectedGroup;

  /// Current article number.
  int? get currentArticle => _connection.currentArticle;

  /// Server capabilities.
  Set<String> get capabilities => Set.unmodifiable(_capabilities);

  /// Creates a new NNTP client.
  NNTPClient({
    required String host,
    int port = 119,
    bool useTLS = false,
    Duration timeout = const Duration(seconds: 30),
  }) : _connection = NNTPConnection(
          host: host,
          port: port,
          useTLS: useTLS,
          timeout: timeout,
        );

  /// Connects to the server.
  ///
  /// Returns the server greeting.
  Future<NNTPResponse> connect() async {
    final greeting = await _connection.connect();

    // Try to get capabilities
    try {
      await fetchCapabilities();
    } catch (_) {
      // Ignore if server doesn't support CAPABILITIES
    }

    return greeting;
  }

  /// Disconnects from the server.
  Future<void> disconnect() async {
    await _connection.disconnect();
  }

  /// Authenticates with username and password.
  Future<void> authenticate(String username, String password) async {
    // Send username
    var response = await _connection.sendCommand('AUTHINFO USER $username');

    if (response.code == NNTPResponse.authAccepted) {
      return; // Some servers accept after username only
    }

    if (response.code != NNTPResponse.continueWithAuth) {
      response.throwIfError();
      throw NNTPAuthException('Unexpected response: ${response.code}', response.code);
    }

    // Send password
    response = await _connection.sendCommand('AUTHINFO PASS $password');

    if (response.code != NNTPResponse.authAccepted) {
      response.throwIfError();
      throw NNTPAuthException('Authentication failed', response.code);
    }
  }

  /// Fetches server capabilities.
  Future<Set<String>> fetchCapabilities() async {
    final response = await _connection.sendCommand('CAPABILITIES', expectMultiline: true);

    if (!response.isSuccess || response.data == null) {
      return _capabilities;
    }

    _capabilities.clear();
    for (final line in response.data!) {
      // First word is the capability name
      final parts = line.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        _capabilities.add(parts.first.toUpperCase());
      }
    }

    return _capabilities;
  }

  /// Switches to reader mode.
  Future<NNTPResponse> modeReader() async {
    final response = await _connection.sendCommand('MODE READER');
    // Update posting status from response
    _connection.postingAllowed = response.code == NNTPResponse.serviceAvailablePosting;
    return response;
  }

  // ==================== Newsgroup Commands ====================

  /// Lists all newsgroups.
  Future<List<Newsgroup>> listGroups({String? pattern}) async {
    final command = pattern != null ? 'LIST ACTIVE $pattern' : 'LIST';
    final response = await _connection.sendCommand(command, expectMultiline: true);

    response.throwIfError();

    final groups = <Newsgroup>[];
    for (final line in response.data ?? []) {
      final group = Newsgroup.fromListActive(line);
      if (group != null) {
        groups.add(group);
      }
    }

    return groups;
  }

  /// Lists newsgroup descriptions.
  Future<Map<String, String>> listDescriptions({String? pattern}) async {
    final command = pattern != null
        ? 'LIST NEWSGROUPS $pattern'
        : 'LIST NEWSGROUPS';
    final response = await _connection.sendCommand(command, expectMultiline: true);

    if (response.code != NNTPResponse.infoFollows) {
      return {};
    }

    final descriptions = <String, String>{};
    for (final line in response.data ?? []) {
      final spaceIndex = line.indexOf(' ');
      if (spaceIndex > 0) {
        final name = line.substring(0, spaceIndex);
        final desc = line.substring(spaceIndex + 1).trim();
        descriptions[name] = desc;
      }
    }

    return descriptions;
  }

  /// Selects a newsgroup.
  ///
  /// Returns the newsgroup info.
  Future<Newsgroup> selectGroup(String name) async {
    final response = await _connection.sendCommand('GROUP $name');

    response.throwIfError();

    final group = Newsgroup.fromGroupResponse('${response.code} ${response.message}');
    if (group == null) {
      throw NNTPProtocolException('Invalid GROUP response: ${response.message}');
    }

    _connection.selectedGroup = name;
    _connection.currentArticle = group.firstArticle;

    return group;
  }

  /// Lists article numbers in the current group.
  Future<List<int>> listGroupArticles({Range? range}) async {
    if (_connection.selectedGroup == null) {
      throw const NNTPNoGroupSelectedException();
    }

    final rangeStr = range?.toNNTPString() ?? '';
    final command = rangeStr.isNotEmpty
        ? 'LISTGROUP ${_connection.selectedGroup} $rangeStr'
        : 'LISTGROUP';
    final response = await _connection.sendCommand(command, expectMultiline: true);

    response.throwIfError();

    return response.data
            ?.map((line) => int.tryParse(line.trim()))
            .whereType<int>()
            .toList() ??
        [];
  }

  // ==================== Article Commands ====================

  /// Fetches a complete article by number.
  Future<NNTPArticle> fetchArticle(int number) async {
    final response = await _connection.sendCommand('ARTICLE $number', expectMultiline: true);

    response.throwIfError();

    if (response.data == null || response.data!.isEmpty) {
      throw NNTPArticleNotFoundException.byNumber(number);
    }

    return NNTPArticle.parse(response.data!.join('\n'), articleNumber: number);
  }

  /// Fetches an article by message ID.
  Future<NNTPArticle> fetchArticleById(String messageId) async {
    // Ensure message ID is in angle brackets
    if (!messageId.startsWith('<')) messageId = '<$messageId>';
    if (!messageId.endsWith('>')) messageId = '$messageId>';

    final response = await _connection.sendCommand('ARTICLE $messageId', expectMultiline: true);

    response.throwIfError();

    if (response.data == null || response.data!.isEmpty) {
      throw NNTPArticleNotFoundException.byMessageId(messageId);
    }

    return NNTPArticle.parse(response.data!.join('\n'));
  }

  /// Fetches article headers only.
  Future<Map<String, String>> fetchHead(int number) async {
    final response = await _connection.sendCommand('HEAD $number', expectMultiline: true);

    response.throwIfError();

    final headers = <String, String>{};
    String? currentKey;
    String? currentValue;

    for (var line in response.data ?? []) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        // Continuation of previous header
        if (currentValue != null) {
          currentValue = '$currentValue ${line.trim()}';
        }
        continue;
      }

      // Save previous header
      if (currentKey != null) {
        headers[currentKey] = currentValue ?? '';
      }

      // Parse new header
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        currentKey = line.substring(0, colonIndex).toLowerCase();
        currentValue = line.substring(colonIndex + 1).trim();
      }
    }

    // Save last header
    if (currentKey != null) {
      headers[currentKey] = currentValue ?? '';
    }

    return headers;
  }

  /// Fetches article body only.
  Future<String> fetchBody(int number) async {
    final response = await _connection.sendCommand('BODY $number', expectMultiline: true);

    response.throwIfError();

    return response.data?.join('\n') ?? '';
  }

  /// Checks if an article exists (STAT command).
  Future<bool> articleExists(int number) async {
    final response = await _connection.sendCommand('STAT $number');
    return response.code == NNTPResponse.statOk;
  }

  /// Checks if an article exists by message ID.
  Future<bool> articleExistsById(String messageId) async {
    if (!messageId.startsWith('<')) messageId = '<$messageId>';
    if (!messageId.endsWith('>')) messageId = '$messageId>';

    final response = await _connection.sendCommand('STAT $messageId');
    return response.code == NNTPResponse.statOk;
  }

  // ==================== Overview Commands ====================

  /// Fetches overview data for articles.
  ///
  /// Uses OVER if available, falls back to XOVER.
  Future<List<OverviewEntry>> fetchOverview({Range? range}) async {
    if (_connection.selectedGroup == null) {
      throw const NNTPNoGroupSelectedException();
    }

    // Try OVER first (RFC 3977), then XOVER (legacy)
    final command = _capabilities.contains('OVER') ? 'OVER' : 'XOVER';
    final rangeStr = range?.toNNTPString() ?? '';
    final fullCommand = rangeStr.isNotEmpty ? '$command $rangeStr' : command;

    final response = await _connection.sendCommand(fullCommand, expectMultiline: true);

    response.throwIfError();

    final entries = <OverviewEntry>[];
    for (final line in response.data ?? []) {
      final entry = OverviewEntry.parse(line);
      if (entry != null) {
        entries.add(entry);
      }
    }

    return entries;
  }

  // ==================== Posting Commands ====================

  /// Posts a new article.
  Future<void> post(NNTPArticle article) async {
    if (!postingAllowed) {
      throw const NNTPPostingException.notAllowed();
    }

    // Start POST command
    final response = await _connection.sendCommand('POST');

    if (response.code != NNTPResponse.sendArticle) {
      response.throwIfError();
      throw const NNTPPostingException.notAllowed();
    }

    // Send article data
    final articleText = article.toPostFormat();
    await _connection.sendRaw(articleText);

    // Wait for final response
    final finalResponse = await _connection.sendCommand('', expectMultiline: false);

    if (finalResponse.code != NNTPResponse.articlePosted) {
      finalResponse.throwIfError();
      throw NNTPPostingException.failed(finalResponse.message);
    }
  }

  // ==================== Misc Commands ====================

  /// Gets server date/time.
  Future<DateTime> fetchDate() async {
    final response = await _connection.sendCommand('DATE');

    response.throwIfError();

    // Response format: "111 YYYYMMDDhhmmss"
    final dateStr = response.message.trim();
    if (dateStr.length < 14) {
      throw NNTPProtocolException('Invalid DATE response: ${response.message}');
    }

    final year = int.parse(dateStr.substring(0, 4));
    final month = int.parse(dateStr.substring(4, 6));
    final day = int.parse(dateStr.substring(6, 8));
    final hour = int.parse(dateStr.substring(8, 10));
    final minute = int.parse(dateStr.substring(10, 12));
    final second = int.parse(dateStr.substring(12, 14));

    return DateTime.utc(year, month, day, hour, minute, second);
  }

  /// Gets server help text.
  Future<List<String>> fetchHelp() async {
    final response = await _connection.sendCommand('HELP', expectMultiline: true);
    return response.data ?? [];
  }

  /// Sends NOOP to keep connection alive.
  Future<void> noop() async {
    await _connection.sendCommand('NOOP');
  }

  /// Lists new newsgroups since a date.
  Future<List<Newsgroup>> fetchNewGroups(DateTime since) async {
    final dateStr = _formatNNTPDate(since);
    final timeStr = _formatNNTPTime(since);

    final response = await _connection.sendCommand(
      'NEWGROUPS $dateStr $timeStr GMT',
      expectMultiline: true,
    );

    response.throwIfError();

    final groups = <Newsgroup>[];
    for (final line in response.data ?? []) {
      final group = Newsgroup.fromListActive(line);
      if (group != null) {
        groups.add(group);
      }
    }

    return groups;
  }

  /// Lists new articles in a group since a date.
  Future<List<String>> fetchNewNews(String group, DateTime since) async {
    final dateStr = _formatNNTPDate(since);
    final timeStr = _formatNNTPTime(since);

    final response = await _connection.sendCommand(
      'NEWNEWS $group $dateStr $timeStr GMT',
      expectMultiline: true,
    );

    response.throwIfError();

    return response.data ?? [];
  }

  String _formatNNTPDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  String _formatNNTPTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h$m$s';
  }
}
