/// Low-level NNTP socket connection management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exceptions.dart';
import 'nntp_response.dart';

/// Manages the low-level socket connection to an NNTP server.
class NNTPConnection {
  /// Server hostname.
  final String host;

  /// Server port (119 for NNTP, 563 for NNTPS).
  final int port;

  /// Whether to use TLS (NNTPS).
  final bool useTLS;

  /// Connection timeout.
  final Duration timeout;

  Socket? _socket;
  SecureSocket? _secureSocket;

  /// Buffer for incoming data.
  final StringBuffer _buffer = StringBuffer();

  /// Stream controller for incoming lines.
  StreamController<String>? _lineController;

  /// Subscription to socket data.
  StreamSubscription<List<int>>? _subscription;

  /// Whether currently connected.
  bool get isConnected => _socket != null || _secureSocket != null;

  /// Keepalive timer.
  Timer? _keepaliveTimer;

  /// Whether posting is allowed on this connection.
  bool postingAllowed = false;

  /// Currently selected newsgroup.
  String? selectedGroup;

  /// Current article number.
  int? currentArticle;

  /// Completer for waiting on greeting.
  Completer<NNTPResponse>? _greetingCompleter;

  NNTPConnection({
    required this.host,
    this.port = 119,
    this.useTLS = false,
    this.timeout = const Duration(seconds: 30),
  });

  /// Connects to the NNTP server.
  ///
  /// Returns the server greeting response.
  Future<NNTPResponse> connect() async {
    if (isConnected) {
      throw const NNTPConnectionException('Already connected');
    }

    _lineController = StreamController<String>.broadcast();
    _greetingCompleter = Completer<NNTPResponse>();

    try {
      if (useTLS) {
        _secureSocket = await SecureSocket.connect(
          host,
          port,
          timeout: timeout,
          onBadCertificate: (cert) => false, // Reject bad certs
        );
        _setupListener(_secureSocket!);
      } else {
        _socket = await Socket.connect(host, port, timeout: timeout);
        _setupListener(_socket!);
      }

      // Wait for server greeting
      final greeting = await _greetingCompleter!.future.timeout(
        timeout,
        onTimeout: () => throw const NNTPTimeoutException('greeting'),
      );

      // Check greeting for posting status
      postingAllowed = greeting.code == NNTPResponse.serviceAvailablePosting;

      // Start keepalive timer (every 60 seconds)
      _startKeepalive();

      return greeting;
    } catch (e) {
      await disconnect();
      if (e is NNTPException) rethrow;
      throw NNTPConnectionException('Failed to connect: $e');
    }
  }

  /// Upgrades connection to TLS using STARTTLS.
  Future<NNTPResponse> startTLS() async {
    if (!isConnected || _socket == null) {
      throw const NNTPConnectionException('Not connected or already using TLS');
    }

    // Send STARTTLS command
    final response = await sendCommand('STARTTLS');
    if (response.code != 382) {
      throw NNTPException('STARTTLS failed', response.code);
    }

    // Upgrade socket to TLS
    _subscription?.cancel();
    _secureSocket = await SecureSocket.secure(
      _socket!,
      host: host,
      onBadCertificate: (cert) => false,
    );
    _socket = null;

    _setupListener(_secureSocket!);
    return response;
  }

  void _setupListener(Socket socket) {
    _subscription = socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(List<int> data) {
    final text = utf8.decode(data, allowMalformed: true);
    _buffer.write(text);

    // Process complete lines
    while (true) {
      final content = _buffer.toString();
      final newlineIndex = content.indexOf('\r\n');
      if (newlineIndex == -1) break;

      final line = content.substring(0, newlineIndex);
      _buffer.clear();
      _buffer.write(content.substring(newlineIndex + 2));

      // Handle greeting if waiting for it
      if (_greetingCompleter != null && !_greetingCompleter!.isCompleted) {
        try {
          final response = NNTPResponse.parseStatusLine(line);
          _greetingCompleter!.complete(response);
        } catch (e) {
          _greetingCompleter!.completeError(e);
        }
      } else {
        _lineController?.add(line);
      }
    }
  }

  void _onError(Object error) {
    _lineController?.addError(NNTPConnectionException('Socket error: $error'));
  }

  void _onDone() {
    _lineController?.close();
    _cleanup();
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (isConnected) {
        try {
          await sendCommand('NOOP');
        } catch (_) {
          // Ignore keepalive errors
        }
      }
    });
  }

  /// Sends a command and waits for the response.
  Future<NNTPResponse> sendCommand(String command, {bool expectMultiline = false}) async {
    if (!isConnected) {
      throw const NNTPConnectionException('Not connected');
    }

    // Send command
    final socket = _secureSocket ?? _socket!;
    socket.write('$command\r\n');
    await socket.flush();

    // Wait for status line
    final statusLine = await _nextLine();
    final response = NNTPResponse.parseStatusLine(statusLine);

    // Check if we need to read multi-line response
    if (expectMultiline || expectsMultilineResponse(response.code)) {
      final data = await _readMultilineResponse();
      return response.withData(data);
    }

    return response;
  }

  /// Sends raw data (for POST command body).
  Future<void> sendRaw(String data) async {
    if (!isConnected) {
      throw const NNTPConnectionException('Not connected');
    }

    final socket = _secureSocket ?? _socket!;
    socket.write(data);
    if (!data.endsWith('\r\n')) {
      socket.write('\r\n');
    }
    socket.write('.\r\n'); // End of data
    await socket.flush();
  }

  Future<String> _nextLine() async {
    if (_lineController == null) {
      throw const NNTPConnectionException('Not connected');
    }

    try {
      return await _lineController!.stream.first.timeout(
        timeout,
        onTimeout: () => throw const NNTPTimeoutException(),
      );
    } on StateError {
      throw const NNTPConnectionException('Connection closed');
    }
  }

  /// Reads a multi-line response until "." terminator.
  Future<List<String>> _readMultilineResponse() async {
    final lines = <String>[];

    while (true) {
      final line = await _nextLine();

      // Single "." marks end of response
      if (line == '.') {
        break;
      }

      // Lines starting with ".." have the first "." removed (dot-stuffing)
      if (line.startsWith('..')) {
        lines.add(line.substring(1));
      } else {
        lines.add(line);
      }
    }

    return lines;
  }

  /// Disconnects from the server.
  Future<void> disconnect() async {
    if (!isConnected) return;

    try {
      // Send QUIT command
      final socket = _secureSocket ?? _socket!;
      socket.write('QUIT\r\n');
      await socket.flush();
    } catch (_) {
      // Ignore errors during disconnect
    }

    _cleanup();
  }

  void _cleanup() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;

    _subscription?.cancel();
    _subscription = null;

    _secureSocket?.destroy();
    _secureSocket = null;

    _socket?.destroy();
    _socket = null;

    _lineController?.close();
    _lineController = null;

    _buffer.clear();

    selectedGroup = null;
    currentArticle = null;
  }

  /// Resets the keepalive timer (call after any command).
  void resetKeepalive() {
    if (_keepaliveTimer != null) {
      _startKeepalive();
    }
  }
}
