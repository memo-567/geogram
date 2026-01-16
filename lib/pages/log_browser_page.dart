/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';
import '../services/crash_service.dart';
import '../services/i18n_service.dart';

/// Log browser page with performant line-based display
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
  final ScrollController _crashScrollController = ScrollController();

  late TabController _tabController;
  bool _isPaused = false;
  String _filterText = '';
  String? _crashLogs;
  Map<String, dynamic>? _heartbeat;
  bool _isLoadingLogFiles = true;

  // Performance: store log lines instead of full string
  List<String> _logLines = [];
  int _totalLogLines = 0;
  bool _logsTruncated = false;

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
    _crashScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;

    if (_tabController.index == 0) {
      _loadCrashLogs();
    } else if (_tabController.index == 1) {
      _reloadAndScrollToBottom();
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
      // Reload logs in background
      final result = await _logService.readTodayLogAsync(maxLines: 1000);
      if (mounted) {
        setState(() {
          _logLines = result.lines;
          _totalLogLines = result.totalLines;
          _logsTruncated = result.truncated;
        });
        if (_tabController.index == 1) {
          _scrollToBottom();
        }
      }
    }
  }

  Future<void> _loadLogFiles() async {
    setState(() => _isLoadingLogFiles = true);

    try {
      // Load log lines in isolate for performance
      final result = await _logService.readTodayLogAsync(maxLines: 1000);
      final heartbeat = await _logService.readHeartbeat();

      if (mounted) {
        setState(() {
          _logLines = result.lines;
          _totalLogLines = result.totalLines;
          _logsTruncated = result.truncated;
          _heartbeat = heartbeat;
          _isLoadingLogFiles = false;
        });
        if (_tabController.index == 1) {
          _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _logLines = [];
          _totalLogLines = 0;
          _logsTruncated = false;
          _heartbeat = null;
          _isLoadingLogFiles = false;
        });
      }
    }
  }

  Future<void> _loadCrashLogs() async {
    try {
      final logs = await _crashService.readAllCrashLogs() ?? await _logService.readCrashLog();
      if (mounted) {
        setState(() => _crashLogs = logs);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _crashLogs = null);
      }
    }
  }

  /// Get filtered log lines
  List<String> _getFilteredLines() {
    if (_filterText.isEmpty) return _logLines;
    final lowerFilter = _filterText.toLowerCase();
    return _logLines.where((line) => line.toLowerCase().contains(lowerFilter)).toList();
  }

  /// Count formal crash reports only (=== CRASH REPORT ===)
  int _countFormalCrashReports(String? crashLogs) {
    if (crashLogs == null || crashLogs.trim().isEmpty) return 0;
    return '=== CRASH REPORT ==='.allMatches(crashLogs).length;
  }

  /// Extract only formal crash reports from crash logs
  String? _extractFormalCrashReports(String? crashLogs) {
    if (crashLogs == null || crashLogs.trim().isEmpty) return null;

    final buffer = StringBuffer();
    const startMarker = '=== CRASH REPORT ===';
    const endMarker = '=== END CRASH REPORT ===';

    int searchStart = 0;
    while (true) {
      final startIndex = crashLogs.indexOf(startMarker, searchStart);
      if (startIndex == -1) break;

      final endIndex = crashLogs.indexOf(endMarker, startIndex);
      if (endIndex == -1) {
        buffer.writeln(crashLogs.substring(startIndex).trim());
        break;
      }

      final crashReport = crashLogs.substring(startIndex, endIndex + endMarker.length);
      buffer.writeln(crashReport.trim());
      buffer.writeln();

      searchStart = endIndex + endMarker.length;
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isPaused ? _i18n.t('log_paused') : _i18n.t('log_resumed')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _clearLog() {
    _logService.clear();
    setState(() {
      _logLines = [];
      _totalLogLines = 0;
      _logsTruncated = false;
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
    await _loadCrashLogs();

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
    final logs = _getFilteredLines().join('\n');
    _copyToClipboard(logs, _i18n.t('log_copied_to_clipboard'));
  }

  void _copyExceptions() {
    final buffer = StringBuffer();

    if (_logLines.isNotEmpty) {
      buffer.writeln('=== TODAY\'S LOG ===');
      buffer.writeln(_logLines.join('\n'));
      buffer.writeln();
    }

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
            Tab(text: 'Crashes', icon: Icon(Icons.bug_report)),
            Tab(text: 'All', icon: Icon(Icons.list)),
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
                _buildCrashPanel(),
                _buildLogPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the "All" log panel with efficient ListView.builder
  Widget _buildLogPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filteredLines = _getFilteredLines();
    final lineCount = filteredLines.length;

    if (_isLoadingLogFiles) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _filterText.isEmpty ? 'Today\'s Log' : 'Today\'s Log (filtered)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_logsTruncated)
                      Text(
                        'Showing last 1000 of $_totalLogLines lines',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
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
                onPressed: lineCount > 0
                    ? () => _copyToClipboard(filteredLines.join('\n'), 'Today\'s log copied')
                    : null,
              ),
            ],
          ),
        ),
        // Log lines with ListView.builder for performance
        Expanded(
          child: lineCount > 0
              ? Container(
                  color: isDark ? Colors.black : Colors.grey[100],
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: filteredLines.length,
                    itemBuilder: (context, index) {
                      final line = filteredLines[index];
                      return _buildLogLine(line, isDark);
                    },
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
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// Build a single log line widget - minimal parsing for performance
  Widget _buildLogLine(String line, bool isDark) {
    // Quick level detection for coloring
    Color textColor = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    if (line.contains('[ERROR]')) {
      textColor = Colors.red;
    } else if (line.contains('[WARN')) {
      textColor = Colors.orange;
    } else if (line.contains('[DEBUG]')) {
      textColor = Colors.grey;
    }

    return InkWell(
      onLongPress: () => _copyToClipboard(line, 'Line copied'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Text(
          line,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.3,
            color: textColor,
          ),
        ),
      ),
    );
  }

  /// Build the crash panel - kept similar to original for highlighted format
  Widget _buildCrashPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final formalCrashReports = _extractFormalCrashReports(_crashLogs);
    final hasCrashLogs = formalCrashReports != null && formalCrashReports.isNotEmpty;
    final crashCount = _countFormalCrashReports(_crashLogs);

    if (_isLoadingLogFiles && _crashLogs == null) {
      _loadCrashLogs();
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      controller: _crashScrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.red),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Crash Reports',
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

          // Crash reports card
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.report_problem, color: Colors.red),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Crash Reports',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$crashCount',
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
                        tooltip: 'Copy Crash Reports',
                        onPressed: hasCrashLogs
                            ? () => _copyToClipboard(formalCrashReports!, 'Crash reports copied')
                            : null,
                      ),
                      if (hasCrashLogs)
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          tooltip: 'Delete crash logs',
                          onPressed: _clearCrashLogs,
                        ),
                    ],
                  ),
                ),
                // Card content
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
                    hasCrashLogs ? formalCrashReports! : 'No crash reports',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      color: hasCrashLogs ? null : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
