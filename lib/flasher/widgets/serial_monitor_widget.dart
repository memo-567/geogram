/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../serial/serial_port.dart';

/// Serial monitor widget for viewing and sending serial data
class SerialMonitorWidget extends StatefulWidget {
  /// Available ports (refreshed externally)
  final List<PortInfo> ports;

  /// Currently selected port (can be pre-selected from flasher tab)
  final PortInfo? selectedPort;

  /// Callback when port selection changes
  final ValueChanged<PortInfo?>? onPortChanged;

  /// Callback to refresh ports
  final VoidCallback? onRefreshPorts;

  const SerialMonitorWidget({
    super.key,
    required this.ports,
    this.selectedPort,
    this.onPortChanged,
    this.onRefreshPorts,
  });

  @override
  State<SerialMonitorWidget> createState() => SerialMonitorWidgetState();
}

/// Public state class to allow external control of the monitor
class SerialMonitorWidgetState extends State<SerialMonitorWidget> {
  // Serial port
  SerialPort? _port;
  bool _isConnected = false;
  bool _isConnecting = false;

  /// Whether the monitor is currently connected
  bool get isConnected => _isConnected;

  /// Connect to the selected port programmatically
  Future<void> connect() => _connect();

  /// Disconnect from the current port programmatically
  Future<void> disconnect() => _disconnect();

  // Settings
  int _baudRate = 115200;
  bool _autoScroll = true;
  bool _showTimestamp = false;
  bool _wordWrap = false; // Default to no wrap
  bool _isPaused = false;
  String _lineEnding = '\n';

  // Data
  final List<_MonitorLine> _lines = [];
  final List<_MonitorLine> _pausedBuffer = []; // Buffer for paused messages
  final int _maxLines = 1000;
  int _rxBytes = 0;
  int _txBytes = 0;

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final List<int> _searchMatches = [];
  int _currentMatchIndex = -1;
  bool _showSearch = false;

  // Controllers
  final _scrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  Timer? _readTimer;

  // Common baud rates
  static const _baudRates = [
    9600,
    19200,
    38400,
    57600,
    74880,
    115200,
    230400,
    460800,
    921600,
  ];

  // Line ending options
  static const _lineEndings = {
    'None': '',
    'LF': '\n',
    'CR': '\r',
    'CRLF': '\r\n',
  };

  @override
  void dispose() {
    _disconnect();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (widget.selectedPort == null) {
      _showError('Please select a serial port');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      _port = SerialPort();
      final opened = await _port!.open(widget.selectedPort!.path, _baudRate);

      if (!opened) {
        throw Exception('Failed to open port');
      }

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      _addSystemLine('Connected to ${widget.selectedPort!.path} at $_baudRate baud');

      // Start reading
      _startReading();
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      _port = null;
      _showError('Connection failed: $e');
    }
  }

  Future<void> _disconnect() async {
    _readTimer?.cancel();
    _readTimer = null;

    if (_port != null) {
      await _port!.close();
      _port = null;
    }

    if (mounted) {
      setState(() {
        _isConnected = false;
      });
      _addSystemLine('Disconnected');
    }
  }

  void _startReading() {
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!_isConnected || _port == null) return;

      try {
        final data = await _port!.read(1024, timeout: const Duration(milliseconds: 10));
        if (data.isNotEmpty) {
          _onDataReceived(data);
        }
      } catch (e) {
        // Ignore read errors during normal operation
      }
    });
  }

  void _onDataReceived(Uint8List data) {
    _rxBytes += data.length;

    // Text mode - decode and handle line breaks
    try {
      final text = utf8.decode(data, allowMalformed: true);

      // Split by newlines but keep partial lines
      final parts = text.split(RegExp(r'[\r\n]+'));
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (part.isNotEmpty) {
          _addLine(part, isRx: true);
        }
      }
    } catch (e) {
      // Fallback to hex on decode error
      final hexStr = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      _addLine('[hex] $hexStr', isRx: true);
    }

    if (_autoScroll && !_isPaused && mounted) {
      _scrollToBottom();
    }
  }

  Future<void> _send(String text) async {
    if (!_isConnected || _port == null || text.isEmpty) return;

    final dataToSend = text + _lineEnding;
    final bytes = Uint8List.fromList(utf8.encode(dataToSend));

    try {
      final written = await _port!.write(bytes);
      _txBytes += written;

      _addLine(text, isRx: false);
      _inputController.clear();

      if (_autoScroll && !_isPaused) {
        _scrollToBottom();
      }
    } catch (e) {
      _showError('Send failed: $e');
    }
  }

  void _addLine(String text, {required bool isRx}) {
    final line = _MonitorLine(
      text: text,
      timestamp: DateTime.now(),
      isRx: isRx,
      isSystem: false,
    );

    if (_isPaused) {
      // Buffer the line when paused
      _pausedBuffer.add(line);
    } else {
      if (!mounted) return;
      setState(() {
        _lines.add(line);

        // Trim old lines
        while (_lines.length > _maxLines) {
          _lines.removeAt(0);
        }

        // Update search matches if searching
        if (_searchQuery.isNotEmpty) {
          _updateSearchMatches();
        }
      });
    }
  }

  void _addSystemLine(String text) {
    if (!mounted) return;
    setState(() {
      _lines.add(_MonitorLine(
        text: text,
        timestamp: DateTime.now(),
        isRx: true,
        isSystem: true,
      ));
    });
  }

  void _togglePause() {
    setState(() {
      if (_isPaused) {
        // Resume - add all buffered lines
        _lines.addAll(_pausedBuffer);
        _pausedBuffer.clear();

        // Trim old lines
        while (_lines.length > _maxLines) {
          _lines.removeAt(0);
        }

        // Update search matches if searching
        if (_searchQuery.isNotEmpty) {
          _updateSearchMatches();
        }

        if (_autoScroll) {
          _scrollToBottom();
        }
      }
      _isPaused = !_isPaused;
    });
  }

  void _clear() {
    setState(() {
      _lines.clear();
      _pausedBuffer.clear();
      _rxBytes = 0;
      _txBytes = 0;
      _searchMatches.clear();
      _currentMatchIndex = -1;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToLine(int lineIndex) {
    if (!_scrollController.hasClients) return;

    // Estimate line height (approx 20 pixels per line with padding)
    const lineHeight = 20.0;
    final targetOffset = lineIndex * lineHeight;

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _copyToClipboard() {
    final text = _lines.map((l) {
      final prefix = _showTimestamp ? '[${_formatTime(l.timestamp)}] ' : '';
      final dir = l.isSystem ? '[SYS] ' : (l.isRx ? '' : '[TX] ');
      return '$prefix$dir${l.text}';
    }).join('\n');

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // Search methods
  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchQuery = '';
        _searchController.clear();
        _searchMatches.clear();
        _currentMatchIndex = -1;
      }
    });
  }

  void _updateSearchMatches() {
    _searchMatches.clear();
    _currentMatchIndex = -1;

    if (_searchQuery.isEmpty) return;

    final query = _searchQuery.toLowerCase();
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].text.toLowerCase().contains(query)) {
        _searchMatches.add(i);
      }
    }

    if (_searchMatches.isNotEmpty) {
      _currentMatchIndex = 0;
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _updateSearchMatches();
      if (_searchMatches.isNotEmpty) {
        _scrollToLine(_searchMatches[_currentMatchIndex]);
      }
    });
  }

  void _goToNextMatch() {
    if (_searchMatches.isEmpty) return;

    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatches.length;
      _scrollToLine(_searchMatches[_currentMatchIndex]);
    });
  }

  void _goToPreviousMatch() {
    if (_searchMatches.isEmpty) return;

    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _searchMatches.length) % _searchMatches.length;
      _scrollToLine(_searchMatches[_currentMatchIndex]);
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Toolbar
        _buildToolbar(theme),

        // Search bar (conditional)
        if (_showSearch) _buildSearchBar(theme),

        const Divider(height: 1),

        // Output area
        Expanded(
          child: _buildOutputArea(theme),
        ),

        const Divider(height: 1),

        // Input area
        _buildInputArea(theme),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    // Find the selected port in the current list (handles port list changes)
    final selectedPort = widget.ports.contains(widget.selectedPort)
        ? widget.selectedPort
        : null;

    // Use orientation to decide layout: wrap in portrait, scroll in landscape
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;

    final toolbarItems = [
          // Port selector
          SizedBox(
            width: isLandscape ? 180 : (isNarrow ? 120 : 150),
            child: DropdownButton<PortInfo>(
              value: selectedPort,
              hint: const Text('Select port'),
              isExpanded: true,
              isDense: true,
              items: widget.ports.map((port) {
                final label = port.product != null
                    ? '${port.path} (${port.product})'
                    : port.path;
                return DropdownMenuItem(
                  value: port,
                  child: Text(label, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: _isConnected ? null : widget.onPortChanged,
            ),
          ),

          // Baud rate selector
          SizedBox(
            width: isLandscape ? 90 : (isNarrow ? 70 : 80),
            child: DropdownButton<int>(
              value: _baudRate,
              isExpanded: true,
              isDense: true,
              items: _baudRates.map((rate) {
                return DropdownMenuItem(
                  value: rate,
                  child: Text('$rate'),
                );
              }).toList(),
              onChanged: _isConnected
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _baudRate = value);
                      }
                    },
            ),
          ),

          // Connect/Disconnect button
          if (_isConnecting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_isConnected)
            FilledButton.tonalIcon(
              onPressed: _disconnect,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Disconnect'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red[100],
                foregroundColor: Colors.red[800],
              ),
            )
          else
            FilledButton.icon(
              onPressed: widget.selectedPort == null ? null : _connect,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Connect'),
            ),

          // Refresh ports
          IconButton(
            onPressed: widget.onRefreshPorts,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Ports',
          ),

          const VerticalDivider(width: 16),

          // Pause button
          IconButton(
            onPressed: _togglePause,
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: _isPaused
                ? 'Resume (${_pausedBuffer.length} buffered)'
                : 'Pause',
            color: _isPaused ? Colors.orange : null,
          ),

          // Clear button
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
          ),

          // Copy button
          IconButton(
            onPressed: _lines.isEmpty ? null : _copyToClipboard,
            icon: const Icon(Icons.copy),
            tooltip: 'Copy All',
          ),

          // Search button
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: 'Search',
            color: _showSearch ? theme.colorScheme.primary : null,
          ),

          const VerticalDivider(width: 16),

          // Auto-scroll toggle
          FilterChip(
            label: const Text('Auto-scroll'),
            selected: _autoScroll,
            onSelected: (v) => setState(() => _autoScroll = v),
          ),

          // Timestamp toggle
          FilterChip(
            label: const Text('Timestamp'),
            selected: _showTimestamp,
            onSelected: (v) => setState(() => _showTimestamp = v),
          ),

          // Word wrap toggle
          FilterChip(
            label: const Text('Wrap'),
            selected: _wordWrap,
            onSelected: (v) => setState(() => _wordWrap = v),
          ),

          // Line ending selector
          SizedBox(
            width: isLandscape ? 70 : 60,
            child: DropdownButton<String>(
              value: _lineEnding,
              isExpanded: true,
              isDense: true,
              items: _lineEndings.entries.map((e) {
                return DropdownMenuItem(
                  value: e.value,
                  child: Text(e.key, style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _lineEnding = value);
                }
              },
            ),
          ),

          // Stats (hide on very narrow screens in portrait)
          if (_isConnected && (isLandscape || screenWidth > 350)) ...[
            const VerticalDivider(width: 16),
            Text(
              'RX: ${_formatBytes(_rxBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green,
              ),
            ),
            Text(
              'TX: ${_formatBytes(_txBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.blue,
              ),
            ),
          ],
        ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: isLandscape
          // Landscape: horizontal scroll to prevent vertical overflow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: toolbarItems
                    .expand((widget) => [widget, const SizedBox(width: 8)])
                    .toList()
                  ..removeLast(),
              ),
            )
          // Portrait: wrap to multiple lines with max height constraint
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: toolbarItems,
                ),
              ),
            ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
              autofocus: true,
            ),
          ),
          const SizedBox(width: 8),
          // Match count
          if (_searchQuery.isNotEmpty)
            Flexible(
              child: Text(
                _searchMatches.isEmpty
                    ? 'No matches'
                    : '${_currentMatchIndex + 1}/${_searchMatches.length}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(width: 8),
          // Previous match
          IconButton(
            onPressed: _searchMatches.isEmpty ? null : _goToPreviousMatch,
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: 'Previous match',
            visualDensity: VisualDensity.compact,
          ),
          // Next match
          IconButton(
            onPressed: _searchMatches.isEmpty ? null : _goToNextMatch,
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Next match',
            visualDensity: VisualDensity.compact,
          ),
          // Close search
          IconButton(
            onPressed: _toggleSearch,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildOutputArea(ThemeData theme) {
    if (_lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terminal,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _isConnected
                  ? 'Waiting for data...'
                  : 'Connect to a serial port to start monitoring',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    // Use SelectionArea to enable text selection across all lines
    final listView = SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _lines.length,
        itemBuilder: (context, index) {
          final line = _lines[index];
          final isCurrentMatch = _searchMatches.isNotEmpty &&
              _currentMatchIndex >= 0 &&
              _currentMatchIndex < _searchMatches.length &&
              _searchMatches[_currentMatchIndex] == index;
          final isMatch = _searchMatches.contains(index);
          return _buildLine(line, theme, index, isMatch: isMatch, isCurrentMatch: isCurrentMatch);
        },
      ),
    );

    Widget content = Container(
      color: theme.brightness == Brightness.dark
          ? Colors.black
          : Colors.grey[100],
      child: _wordWrap
          ? listView
          : Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 2000, // Wide enough for most content
                  child: listView,
                ),
              ),
            ),
    );

    // Show pause indicator
    if (_isPaused) {
      content = Stack(
        children: [
          content,
          Positioned(
            top: 8,
            right: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pause, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Paused (${_pausedBuffer.length} buffered)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }

  Widget _buildLine(
    _MonitorLine line,
    ThemeData theme,
    int index, {
    bool isMatch = false,
    bool isCurrentMatch = false,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    Color textColor;
    if (line.isSystem) {
      textColor = Colors.grey;
    } else if (line.isRx) {
      textColor = isDark ? Colors.green[300]! : Colors.green[800]!;
    } else {
      textColor = isDark ? Colors.blue[300]! : Colors.blue[800]!;
    }

    final timestamp = _showTimestamp
        ? '[${_formatTime(line.timestamp)}] '
        : '';

    final prefix = line.isSystem
        ? '[SYS] '
        : (line.isRx ? '' : '[TX] ');

    final fullText = '$timestamp$prefix${line.text}';

    // Highlight search matches
    Widget textWidget;
    if (_searchQuery.isNotEmpty && isMatch) {
      textWidget = _buildHighlightedText(
        fullText,
        _searchQuery,
        textColor,
        isCurrentMatch,
        theme,
      );
    } else {
      textWidget = Text(
        fullText,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: textColor,
          height: 1.4,
        ),
        maxLines: _wordWrap ? null : 1,
      );
    }

    // Background highlight for current match
    if (isCurrentMatch) {
      return Container(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: textWidget,
      );
    }

    return textWidget;
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    Color baseColor,
    bool isCurrentMatch,
    ThemeData theme,
  ) {
    final queryLower = query.toLowerCase();
    final textLower = text.toLowerCase();

    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = textLower.indexOf(queryLower, start);
      if (index == -1) {
        // Add remaining text
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          backgroundColor: isCurrentMatch
              ? theme.colorScheme.primary
              : Colors.yellow,
          color: isCurrentMatch ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: baseColor,
          height: 1.4,
        ),
        children: spans,
      ),
      maxLines: _wordWrap ? null : 1,
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Input field
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              decoration: InputDecoration(
                hintText: _isConnected ? 'Type command...' : 'Connect first',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: const OutlineInputBorder(),
              ),
              enabled: _isConnected,
              onSubmitted: _send,
              textInputAction: TextInputAction.send,
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          FilledButton.icon(
            onPressed: _isConnected
                ? () => _send(_inputController.text)
                : null,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

/// A single line in the monitor output
class _MonitorLine {
  final String text;
  final DateTime timestamp;
  final bool isRx;
  final bool isSystem;

  _MonitorLine({
    required this.text,
    required this.timestamp,
    required this.isRx,
    required this.isSystem,
  });
}
