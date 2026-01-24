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
  bool _hexMode = false;
  bool _wordWrap = true;
  String _lineEnding = '\n';

  // Data
  final List<_MonitorLine> _lines = [];
  final int _maxLines = 1000;
  int _rxBytes = 0;
  int _txBytes = 0;

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
    'LF (\\n)': '\n',
    'CR (\\r)': '\r',
    'CR+LF': '\r\n',
  };

  @override
  void dispose() {
    _disconnect();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
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

    if (_hexMode) {
      // Hex mode - show raw bytes
      final hexStr = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      _addLine(hexStr, isRx: true);
    } else {
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
    }

    if (_autoScroll && mounted) {
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

      if (_autoScroll) {
        _scrollToBottom();
      }
    } catch (e) {
      _showError('Send failed: $e');
    }
  }

  void _addLine(String text, {required bool isRx}) {
    setState(() {
      _lines.add(_MonitorLine(
        text: text,
        timestamp: DateTime.now(),
        isRx: isRx,
        isSystem: false,
      ));

      // Trim old lines
      while (_lines.length > _maxLines) {
        _lines.removeAt(0);
      }
    });
  }

  void _addSystemLine(String text) {
    setState(() {
      _lines.add(_MonitorLine(
        text: text,
        timestamp: DateTime.now(),
        isRx: true,
        isSystem: true,
      ));
    });
  }

  void _clear() {
    setState(() {
      _lines.clear();
      _rxBytes = 0;
      _txBytes = 0;
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Port selector
          SizedBox(
            width: 180,
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
            width: 90,
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

          // Hex mode toggle
          FilterChip(
            label: const Text('Hex'),
            selected: _hexMode,
            onSelected: (v) => setState(() => _hexMode = v),
          ),

          // Word wrap toggle
          FilterChip(
            label: const Text('Wrap'),
            selected: _wordWrap,
            onSelected: (v) => setState(() => _wordWrap = v),
          ),

          // Stats
          if (_isConnected) ...[
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

    final listView = ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        return _buildLine(line, theme);
      },
    );

    return Container(
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
  }

  Widget _buildLine(_MonitorLine line, ThemeData theme) {
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

    return SelectableText(
      '$timestamp$prefix${line.text}',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: textColor,
        height: 1.4,
      ),
      maxLines: _wordWrap ? null : 1,
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Line ending selector
          SizedBox(
            width: 90,
            child: DropdownButton<String>(
              value: _lineEnding,
              isExpanded: true,
              isDense: true,
              items: _lineEndings.entries.map((e) {
                return DropdownMenuItem(
                  value: e.value,
                  child: Text(e.key),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _lineEnding = value);
                }
              },
            ),
          ),

          const SizedBox(width: 8),

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
