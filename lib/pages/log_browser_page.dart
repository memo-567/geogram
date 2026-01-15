/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';
import '../services/crash_service.dart';
import '../services/i18n_service.dart';

/// Log entry parsed with level information
class ParsedLogEntry {
  final String raw;
  final String timestamp;
  final LogLevel level;
  final String message;

  ParsedLogEntry({
    required this.raw,
    required this.timestamp,
    required this.level,
    required this.message,
  });

  /// Parse a log entry string into its components
  factory ParsedLogEntry.parse(String line) {
    // Format: "2025-01-13 10:30:45.123 [INFO ] message"
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[(\w+)\s*\] (.*)$').firstMatch(line);

    if (match != null) {
      final levelStr = match.group(2)!.trim().toLowerCase();
      LogLevel level;
      switch (levelStr) {
        case 'error':
          level = LogLevel.error;
          break;
        case 'warn':
          level = LogLevel.warn;
          break;
        case 'debug':
          level = LogLevel.debug;
          break;
        default:
          level = LogLevel.info;
      }

      return ParsedLogEntry(
        raw: line,
        timestamp: match.group(1)!,
        level: level,
        message: match.group(3)!,
      );
    }

    // Fallback for unparseable lines
    return ParsedLogEntry(
      raw: line,
      timestamp: '',
      level: LogLevel.info,
      message: line,
    );
  }

  /// Check if this entry looks like an exception/error
  bool get isException {
    final lowerMessage = message.toLowerCase();
    return level == LogLevel.error ||
        lowerMessage.contains('exception') ||
        lowerMessage.contains('error:') ||
        lowerMessage.contains('failed') ||
        lowerMessage.contains('crash') ||
        message.contains('Stack Trace:') ||
        message.startsWith('at ') ||
        RegExp(r'#\d+ ').hasMatch(message);
  }
}

/// Grouped log entry with occurrence count
class GroupedLogEntry {
  final String message;
  final LogLevel level;
  final String lastTimestamp;
  final int count;

  GroupedLogEntry({
    required this.message,
    required this.level,
    required this.lastTimestamp,
    required this.count,
  });

  /// Group log entries by message content, counting occurrences
  static List<GroupedLogEntry> groupByMessage(List<ParsedLogEntry> entries) {
    final Map<String, List<ParsedLogEntry>> grouped = {};

    for (final entry in entries) {
      final key = entry.message;
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    // Convert to list of GroupedLogEntry, sorted by last occurrence (most recent first)
    final result = grouped.entries.map((e) {
      final entriesForMessage = e.value;
      // Sort by timestamp descending to get the most recent
      entriesForMessage.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return GroupedLogEntry(
        message: e.key,
        level: entriesForMessage.first.level,
        lastTimestamp: entriesForMessage.first.timestamp,
        count: entriesForMessage.length,
      );
    }).toList();

    // Sort by last timestamp descending (most recent first)
    result.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));

    return result;
  }
}

/// Log browser page with consistent UI and exceptions panel
class LogBrowserPage extends StatefulWidget {
  const LogBrowserPage({super.key});

  @override
  State<LogBrowserPage> createState() => _LogBrowserPageState();
}

class _LogBrowserPageState extends State<LogBrowserPage> with SingleTickerProviderStateMixin {
  final LogService _logService = LogService();
  final CrashService _crashService = CrashService();
  final I18nService _i18n = I18nService();
  final TextEditingController _filterController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  final ScrollController _exceptionScrollController = ScrollController();

  late TabController _tabController;
  bool _isPaused = false;
  String _filterText = '';
  String? _crashLogs;
  String? _todayLog;
  Map<String, dynamic>? _heartbeat;
  ParsedLogEntry? _selectedEntry;
  bool _isLoadingLogFiles = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _i18n.languageNotifier.addListener(_onLanguageChanged);
    _logService.addListener(_onLogUpdate);
    _loadLogFiles();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _i18n.languageNotifier.removeListener(_onLanguageChanged);
    _logService.removeListener(_onLogUpdate);
    _filterController.dispose();
    _logScrollController.dispose();
    _exceptionScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;

    // Reload data when switching tabs
    if (_tabController.index == 0) {
      // "All" tab - reload and scroll to bottom
      _reloadAndScrollToBottom();
    } else if (_tabController.index == 1) {
      // "Crashes" tab - reload crash logs
      _loadLogFiles();
    }
  }

  Future<void> _reloadAndScrollToBottom() async {
    await _loadLogFiles();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onLanguageChanged() {
    setState(() {});
  }

  void _onLogUpdate(String message) async {
    if (!_isPaused && mounted) {
      // Reload logs to update counters
      final todayLog = await _logService.readTodayLog();
      final crashLogs = await _crashService.readAllCrashLogs() ?? await _logService.readCrashLog();
      if (mounted) {
        setState(() {
          _todayLog = todayLog;
          _crashLogs = crashLogs;
        });
        // Auto-scroll to bottom if on "All" tab
        if (_tabController.index == 0) {
          _scrollToBottom();
        }
      }
    }
  }

  /// Count formal crash reports only (=== CRASH REPORT ===)
  int _countFormalCrashReports(String? crashLogs) {
    if (crashLogs == null || crashLogs.trim().isEmpty) return 0;
    final separator = '=== CRASH REPORT ===';
    return separator.allMatches(crashLogs).length;
  }

  /// Extract only formal crash reports from crash logs
  /// Returns text containing only the === CRASH REPORT === blocks
  String? _extractFormalCrashReports(String? crashLogs) {
    if (crashLogs == null || crashLogs.trim().isEmpty) return null;

    final buffer = StringBuffer();
    final startMarker = '=== CRASH REPORT ===';
    final endMarker = '=== END CRASH REPORT ===';

    int searchStart = 0;
    while (true) {
      final startIndex = crashLogs.indexOf(startMarker, searchStart);
      if (startIndex == -1) break;

      final endIndex = crashLogs.indexOf(endMarker, startIndex);
      if (endIndex == -1) {
        // No end marker found, take rest of content
        buffer.writeln(crashLogs.substring(startIndex).trim());
        break;
      }

      // Extract the full crash report including end marker
      final crashReport = crashLogs.substring(startIndex, endIndex + endMarker.length);
      buffer.writeln(crashReport.trim());
      buffer.writeln();

      searchStart = endIndex + endMarker.length;
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  Future<void> _loadLogFiles() async {
    setState(() => _isLoadingLogFiles = true);

    try {
      final todayLog = await _logService.readTodayLog();
      final logs = await _crashService.readAllCrashLogs() ?? await _logService.readCrashLog();
      final heartbeat = await _logService.readHeartbeat();
      if (mounted) {
        setState(() {
          _todayLog = todayLog;
          _crashLogs = logs;
          _heartbeat = heartbeat;
          _isLoadingLogFiles = false;
        });
        // Scroll to bottom if on "All" tab
        if (_tabController.index == 0) {
          _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _todayLog = null;
          _crashLogs = null;
          _heartbeat = null;
          _isLoadingLogFiles = false;
        });
      }
    }
  }

  List<ParsedLogEntry> _getParsedLogs() {
    return _logService.messages.map((m) => ParsedLogEntry.parse(m)).toList();
  }

  List<ParsedLogEntry> _getFilteredLogs(LogLevel? levelFilter) {
    var logs = _getParsedLogs();

    // Apply level filter
    if (levelFilter != null) {
      logs = logs.where((log) => log.level == levelFilter).toList();
    }

    // Apply text filter
    if (_filterText.isNotEmpty) {
      logs = logs.where((log) =>
          log.raw.toLowerCase().contains(_filterText.toLowerCase())).toList();
    }

    return logs;
  }

  List<ParsedLogEntry> _getExceptionLogs() {
    return _getParsedLogs().where((log) => log.isException).toList();
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isPaused ? _i18n.t('log_paused') : _i18n.t('log_resumed')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _clearLog() {
    // Clear in-memory logs and displayed content (not files on disk)
    _logService.clear();
    setState(() {
      _todayLog = null;
      _selectedEntry = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_i18n.t('log_cleared')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clearCrashLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Crash Logs?'),
        content: const Text('This will delete all crash logs. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _crashService.clearAllCrashLogs();
    await _loadLogFiles();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crash logs cleared')),
      );
    }
  }

  void _copyToClipboard(String text, String successMessage) {
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _copyAllLogs() {
    final logs = _getFilteredLogs(null).map((l) => l.raw).join('\n');
    _copyToClipboard(logs, _i18n.t('log_copied_to_clipboard'));
  }

  void _copyExceptions() {
    final buffer = StringBuffer();

    if (_todayLog != null && _todayLog!.trim().isNotEmpty) {
      buffer.writeln('=== TODAY\'S LOG ===');
      buffer.writeln(_todayLog!.trim());
      buffer.writeln();
    }

    // Add runtime exceptions
    final exceptionLogs = _getExceptionLogs();
    if (exceptionLogs.isNotEmpty) {
      buffer.writeln('=== RUNTIME ERRORS ===');
      for (final log in exceptionLogs) {
        buffer.writeln(log.raw);
      }
      buffer.writeln();
    }

    // Add crash logs
    if (_crashLogs != null && _crashLogs!.isNotEmpty) {
      buffer.writeln(_crashLogs);
    }

    if (buffer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to copy')),
      );
      return;
    }

    _copyToClipboard(buffer.toString(), 'Logs copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_i18n.t('collection_type_log')),
        actions: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: _isPaused ? _i18n.t('resume') : _i18n.t('pause'),
            onPressed: _togglePause,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _loadLogFiles();
                  break;
                case 'clear_log':
                  _clearLog();
                  break;
                case 'copy_all':
                  _copyAllLogs();
                  break;
                case 'copy_exceptions':
                  _copyExceptions();
                  break;
                case 'clear_crashes':
                  _clearCrashLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_log',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear Log'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'copy_all',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('Copy All Logs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'copy_exceptions',
                child: ListTile(
                  leading: Icon(Icons.bug_report),
                  title: Text('Copy Exceptions'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_crashes',
                child: ListTile(
                  leading: Icon(Icons.delete_forever, color: Colors.red),
                  title: Text('Clear Crash Logs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All', icon: Icon(Icons.list)),
            Tab(text: 'Crashes', icon: Icon(Icons.bug_report)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: _i18n.t('filter_logs'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixIcon: _filterText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterController.clear();
                          setState(() => _filterText = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _filterText = value);
              },
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTodayLogPanel(), // Today's log
                _buildCrashPanel(), // Crashes
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayLogPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Filter log lines if search text is provided
    String filteredLog = '';
    if (_todayLog != null && _todayLog!.trim().isNotEmpty) {
      if (_filterText.isEmpty) {
        filteredLog = _todayLog!.trim();
      } else {
        final lines = _todayLog!.split('\n');
        final filtered = lines.where((line) =>
            line.toLowerCase().contains(_filterText.toLowerCase())).toList();
        filteredLog = filtered.join('\n');
      }
    }

    final hasLogs = filteredLog.isNotEmpty;
    final lineCount = hasLogs
        ? filteredLog.split('\n').where((l) => l.trim().isNotEmpty).length
        : 0;

    if (_isLoadingLogFiles) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Fixed header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.article_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _filterText.isEmpty ? 'Today\'s Log' : 'Today\'s Log (filtered)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$lineCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy Today\'s Log',
                onPressed: hasLogs
                    ? () => _copyToClipboard(filteredLog, 'Today\'s log copied')
                    : null,
              ),
            ],
          ),
        ),
        // Scrollable content
        Expanded(
          child: hasLogs
              ? Container(
                  width: double.infinity,
                  color: isDark ? Colors.black : Colors.grey[100],
                  child: SingleChildScrollView(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      filteredLog,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.article_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _filterText.isEmpty ? 'No logs yet' : 'No matching logs',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLogTile(ParsedLogEntry entry) {
    Color levelColor;
    IconData levelIcon;

    switch (entry.level) {
      case LogLevel.error:
        levelColor = Colors.red;
        levelIcon = Icons.error;
        break;
      case LogLevel.warn:
        levelColor = Colors.orange;
        levelIcon = Icons.warning;
        break;
      case LogLevel.debug:
        levelColor = Colors.grey;
        levelIcon = Icons.bug_report;
        break;
      default:
        levelColor = Colors.blue;
        levelIcon = Icons.info;
    }

    final isSelected = _selectedEntry?.raw == entry.raw;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: isSelected ? levelColor.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedEntry = isSelected ? null : entry;
          });
        },
        onLongPress: () {
          _copyToClipboard(entry.raw, 'Log entry copied');
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(levelIcon, color: levelColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    entry.timestamp,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  if (entry.isException)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'EXCEPTION',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.message,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                maxLines: isSelected ? null : 2,
                overflow: isSelected ? null : TextOverflow.ellipsis,
              ),
              if (isSelected) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      onPressed: () => _copyToClipboard(entry.raw, 'Log entry copied'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCrashPanel() {
    final exceptionLogs = _getExceptionLogs();
    final formalCrashReports = _extractFormalCrashReports(_crashLogs);
    final hasCrashLogs = formalCrashReports != null && formalCrashReports.isNotEmpty;

    if (_isLoadingLogFiles) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      controller: _exceptionScrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Copy all button
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.red),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Exceptions & Crash Reports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy All'),
                onPressed: _copyExceptions,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Copy these logs and share them to help fix issues.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Runtime errors from log (grouped by message)
          if (exceptionLogs.isNotEmpty) ...[
            _buildGroupedExceptionSection(
              title: 'Runtime Errors',
              icon: Icons.error,
              entries: GroupedLogEntry.groupByMessage(exceptionLogs),
              accentColor: Colors.orange,
            ),
            const SizedBox(height: 16),
          ],

          // Crash logs (formal crash reports only)
          _buildExceptionSection(
            title: 'Crash Reports',
            icon: Icons.report_problem,
            content: hasCrashLogs ? formalCrashReports! : 'No crash reports',
            count: _countFormalCrashReports(_crashLogs),
            trailingAction: hasCrashLogs
                ? IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: 'Delete crash log',
                    onPressed: _clearCrashLogs,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionSection({
    required String title,
    required IconData icon,
    required String content,
    required int count,
    Color accentColor = Colors.red,
    Widget? trailingAction,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy $title',
                  onPressed: () => _copyToClipboard(content, '$title copied'),
                ),
                if (trailingAction != null) trailingAction,
              ],
            ),
          ),
          // Content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedExceptionSection({
    required String title,
    required IconData icon,
    required List<GroupedLogEntry> entries,
    Color accentColor = Colors.red,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final uniqueCount = entries.length;
    final totalCount = entries.fold<int>(0, (sum, e) => sum + e.count);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$uniqueCount unique ($totalCount total)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy $title',
                  onPressed: () {
                    final content = entries.map((e) =>
                        '${e.count > 1 ? "[x${e.count}] " : ""}${e.message}').join('\n');
                    _copyToClipboard(content, '$title copied');
                  },
                ),
              ],
            ),
          ),
          // Content - list of grouped entries
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.map((entry) => _buildGroupedEntryTile(entry, accentColor, isDark)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedEntryTile(GroupedLogEntry entry, Color accentColor, bool isDark) {
    Color levelColor;
    IconData levelIcon;

    switch (entry.level) {
      case LogLevel.error:
        levelColor = Colors.red;
        levelIcon = Icons.error;
        break;
      case LogLevel.warn:
        levelColor = Colors.orange;
        levelIcon = Icons.warning;
        break;
      case LogLevel.debug:
        levelColor = Colors.grey;
        levelIcon = Icons.bug_report;
        break;
      default:
        levelColor = Colors.blue;
        levelIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(levelIcon, color: levelColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last: ${entry.lastTimestamp}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (entry.count > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'x${entry.count}',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeartbeatCard() {
    final hb = _heartbeat ?? {};
    final connected = hb['connected'] == true;
    final keepAlive = hb['keepAliveEnabled'] == true;
    final station = (hb['stationUrl'] as String?) ?? '—';

    Widget buildRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.link : Icons.link_off,
                  color: connected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Background Service',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (keepAlive)
                  const Chip(
                    label: Text('Keep-alive'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            buildRow('Station', station),
            buildRow('Last ping', _formatTimestamp(hb['lastPing'] as String?)),
            buildRow('Last pong', _formatTimestamp(hb['lastPong'] as String?)),
            buildRow('Last reconnect', _formatTimestamp(hb['lastReconnectSuccess'] as String?)),
            buildRow('Last disconnect', _formatTimestamp(hb['lastDisconnect'] as String?)),
            buildRow('Updated', _formatTimestamp(hb['updatedAt'] as String?)),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }
}
