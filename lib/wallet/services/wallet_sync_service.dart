/// Service for P2P synchronization of wallet data.
///
/// Uses ConnectionManager for transport-agnostic communication.
/// Handles incoming sync requests and outgoing sync pushes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/debt_ledger.dart';
import '../../connection/connection_manager.dart';
import '../../connection/transport_message.dart';
import '../../models/profile.dart';
import '../../services/log_service.dart';
import 'wallet_service.dart';

/// Request types for wallet sync
enum WalletRequestType {
  debtApproval,
  amendmentApproval,
  witnessRequest,
  settlementConfirmation,
}

/// Represents a pending sync request
class WalletSyncRequest {
  /// Request ID
  final String id;

  /// Request type
  final WalletRequestType type;

  /// The debt ledger data
  final DebtLedger ledger;

  /// Sender callsign
  final String senderCallsign;

  /// Sender npub
  final String senderNpub;

  /// When the request was received
  final DateTime receivedAt;

  /// When the request expires (30 days default)
  final DateTime expiresAt;

  WalletSyncRequest({
    required this.id,
    required this.type,
    required this.ledger,
    required this.senderCallsign,
    required this.senderNpub,
    required this.receivedAt,
    DateTime? expiresAt,
  }) : expiresAt = expiresAt ?? receivedAt.add(const Duration(days: 30));

  /// Check if request is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'ledger_content': ledger.export(),
    'sender_callsign': senderCallsign,
    'sender_npub': senderNpub,
    'received_at': receivedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
  };

  /// Parse from JSON
  factory WalletSyncRequest.fromJson(Map<String, dynamic> json) {
    return WalletSyncRequest(
      id: json['id'] as String,
      type: WalletRequestType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => WalletRequestType.debtApproval,
      ),
      ledger: DebtLedger.parse(json['ledger_content'] as String),
      senderCallsign: json['sender_callsign'] as String,
      senderNpub: json['sender_npub'] as String,
      receivedAt: DateTime.parse(json['received_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// Service for P2P wallet synchronization
class WalletSyncService {
  static final WalletSyncService _instance = WalletSyncService._internal();
  factory WalletSyncService() => _instance;
  WalletSyncService._internal();

  String? _basePath;
  StreamSubscription<TransportMessage>? _incomingSubscription;

  /// Stream controller for incoming requests
  final _requestsController = StreamController<WalletSyncRequest>.broadcast();

  /// Stream of incoming sync requests
  Stream<WalletSyncRequest> get incomingRequests => _requestsController.stream;

  /// Maximum pending requests per sender
  static const int maxPendingPerSender = 5;

  /// Request expiry duration
  static const Duration requestExpiry = Duration(days: 30);

  /// Check if the service is initialized
  bool get isInitialized => _basePath != null;

  /// Initialize the sync service
  Future<void> initialize(String appPath) async {
    _basePath = appPath;

    // Ensure requests directory exists
    final requestsDir = Directory(path.join(_basePath!, 'requests'));
    if (!await requestsDir.exists()) {
      await requestsDir.create(recursive: true);
    }

    // Start listening for incoming messages
    _startListening();

    LogService().log('WalletSyncService: Initialized');
  }

  /// Reset the service
  void dispose() {
    _incomingSubscription?.cancel();
    _incomingSubscription = null;
    _basePath = null;
  }

  /// Start listening for incoming wallet sync messages
  void _startListening() {
    _incomingSubscription?.cancel();
    _incomingSubscription = ConnectionManager().incomingMessages.listen(_handleIncomingMessage);
  }

  /// Handle incoming transport message
  void _handleIncomingMessage(TransportMessage message) {
    if (message.type != TransportMessageType.apiRequest) return;

    final data = message.payload;
    if (data == null) return;

    final messagePath = data['path'] as String?;
    if (messagePath == null) return;

    // Handle wallet sync endpoints
    if (messagePath.startsWith('/api/wallet/')) {
      _handleWalletRequest(message, data);
    }
  }

  /// Handle wallet API request
  Future<void> _handleWalletRequest(TransportMessage message, Map<String, dynamic> data) async {
    final messagePath = data['path'] as String;
    final method = data['method'] as String? ?? 'GET';
    final body = data['body'];

    try {
      if (messagePath == '/api/wallet/sync' && method == 'POST') {
        await _handleSyncRequest(message, body);
      } else if (messagePath == '/api/wallet/requests' && method == 'GET') {
        await _handleListRequests(message);
      }
      // Other endpoints can be added here
    } catch (e) {
      LogService().log('WalletSyncService: Error handling request: $e');
    }
  }

  /// Handle incoming sync request
  Future<void> _handleSyncRequest(TransportMessage message, dynamic body) async {
    if (_basePath == null) return;
    if (body == null) return;

    try {
      final requestData = body is Map<String, dynamic> ? body : jsonDecode(body as String);

      final typeStr = requestData['type'] as String? ?? 'debt_approval';
      final type = WalletRequestType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => WalletRequestType.debtApproval,
      );

      final ledgerContent = requestData['ledger'] as String?;
      if (ledgerContent == null) return;

      final ledger = DebtLedger.parse(ledgerContent);

      // Check rate limiting (for incoming messages, targetCallsign is the sender)
      final senderCallsign = message.targetCallsign;
      final pendingCount = await _countPendingFromSender(senderCallsign);
      if (pendingCount >= maxPendingPerSender) {
        LogService().log('WalletSyncService: Rate limit exceeded for $senderCallsign');
        return;
      }

      // Create request
      final request = WalletSyncRequest(
        id: _generateRequestId(),
        type: type,
        ledger: ledger,
        senderCallsign: senderCallsign,
        senderNpub: requestData['sender_npub'] as String? ?? '',
        receivedAt: DateTime.now(),
      );

      // Save to disk
      await _saveRequest(request);

      // Notify listeners
      _requestsController.add(request);

      LogService().log('WalletSyncService: Received sync request ${request.id} from ${request.senderCallsign}');
    } catch (e) {
      LogService().log('WalletSyncService: Error processing sync request: $e');
    }
  }

  /// Handle list requests
  Future<void> _handleListRequests(TransportMessage message) async {
    // This would return pending requests - implementation depends on response mechanism
  }

  // ============ Outgoing Sync ============

  /// Send a debt to counterparty for approval
  Future<bool> sendForApproval({
    required DebtLedger ledger,
    required String targetCallsign,
    required Profile profile,
  }) async {
    return _sendSync(
      ledger: ledger,
      targetCallsign: targetCallsign,
      type: WalletRequestType.debtApproval,
      profile: profile,
    );
  }

  /// Send an amendment (payment, session, etc.) for confirmation
  Future<bool> sendAmendment({
    required DebtLedger ledger,
    required String targetCallsign,
    required Profile profile,
  }) async {
    return _sendSync(
      ledger: ledger,
      targetCallsign: targetCallsign,
      type: WalletRequestType.amendmentApproval,
      profile: profile,
    );
  }

  /// Request a witness signature
  Future<bool> requestWitness({
    required DebtLedger ledger,
    required String witnessCallsign,
    required Profile profile,
  }) async {
    return _sendSync(
      ledger: ledger,
      targetCallsign: witnessCallsign,
      type: WalletRequestType.witnessRequest,
      profile: profile,
    );
  }

  /// Send sync to counterparty
  Future<bool> _sendSync({
    required DebtLedger ledger,
    required String targetCallsign,
    required WalletRequestType type,
    required Profile profile,
  }) async {
    try {
      final result = await ConnectionManager().apiRequest(
        callsign: targetCallsign,
        method: 'POST',
        path: '/api/wallet/sync',
        body: {
          'type': type.name,
          'ledger': ledger.export(),
          'sender_npub': profile.npub,
        },
        queueIfOffline: true,
      );

      if (result.success) {
        LogService().log('WalletSyncService: Sent ${type.name} to $targetCallsign');
        return true;
      } else {
        LogService().log('WalletSyncService: Failed to send to $targetCallsign: ${result.error}');
        return false;
      }
    } catch (e) {
      LogService().log('WalletSyncService: Error sending sync: $e');
      return false;
    }
  }

  // ============ Request Management ============

  /// Get all pending requests
  Future<List<WalletSyncRequest>> getPendingRequests() async {
    if (_basePath == null) return [];

    try {
      final requestsDir = Directory(path.join(_basePath!, 'requests'));
      if (!await requestsDir.exists()) return [];

      final requests = <WalletSyncRequest>[];
      await for (final entity in requestsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final request = WalletSyncRequest.fromJson(jsonDecode(content));
            if (!request.isExpired) {
              requests.add(request);
            } else {
              // Clean up expired request
              await entity.delete();
            }
          } catch (e) {
            LogService().log('WalletSyncService: Error reading request: $e');
          }
        }
      }

      // Sort by received date, newest first
      requests.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      return requests;
    } catch (e) {
      LogService().log('WalletSyncService: Error listing requests: $e');
      return [];
    }
  }

  /// Get a pending request by ID
  Future<WalletSyncRequest?> getRequest(String requestId) async {
    if (_basePath == null) return null;

    try {
      final file = File(path.join(_basePath!, 'requests', '$requestId.json'));
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      return WalletSyncRequest.fromJson(jsonDecode(content));
    } catch (e) {
      LogService().log('WalletSyncService: Error reading request: $e');
      return null;
    }
  }

  /// Approve a pending request
  Future<bool> approveRequest(String requestId, Profile profile) async {
    final request = await getRequest(requestId);
    if (request == null) return false;

    // Add appropriate entry based on request type
    switch (request.type) {
      case WalletRequestType.debtApproval:
        // First, save the incoming ledger to local wallet so confirmDebt can find it
        final saved = await _saveLedgerToLocalWallet(request.ledger);
        if (!saved) {
          LogService().log('WalletSyncService: Failed to save incoming ledger locally');
          return false;
        }

        // Add confirm entry (debtor signs)
        final success = await WalletService().confirmDebt(
          debtId: request.ledger.id,
          author: profile.callsign,
          content: 'I accept this debt.',
          profile: profile,
        );
        if (success) {
          await _deleteRequest(requestId);
          // Send updated ledger back to creditor
          final updatedLedger = await WalletService().findDebt(request.ledger.id);
          if (updatedLedger != null) {
            await sendAmendment(
              ledger: updatedLedger,
              targetCallsign: request.senderCallsign,
              profile: profile,
            );
          }
        }
        return success;

      case WalletRequestType.amendmentApproval:
        // Merge the incoming ledger with local
        final success = await _mergeLedger(request.ledger);
        if (success) {
          await _deleteRequest(requestId);
        }
        return success;

      case WalletRequestType.witnessRequest:
        // Add witness entry
        final success = await WalletService().addWitness(
          debtId: request.ledger.id,
          author: profile.callsign,
          content: 'I witness this agreement.',
          profile: profile,
        );
        if (success) {
          await _deleteRequest(requestId);
          // Send updated ledger back
          final updatedLedger = await WalletService().findDebt(request.ledger.id);
          if (updatedLedger != null) {
            await sendAmendment(
              ledger: updatedLedger,
              targetCallsign: request.senderCallsign,
              profile: profile,
            );
          }
        }
        return success;

      case WalletRequestType.settlementConfirmation:
        // Merge and confirm settlement
        final success = await _mergeLedger(request.ledger);
        if (success) {
          await _deleteRequest(requestId);
        }
        return success;
    }
  }

  /// Reject a pending request
  Future<bool> rejectRequest(String requestId, {String? reason, Profile? profile}) async {
    final request = await getRequest(requestId);
    if (request == null) return false;

    // For debt approval requests, add a reject entry
    if (request.type == WalletRequestType.debtApproval && profile != null) {
      await WalletService().rejectDebt(
        debtId: request.ledger.id,
        author: profile.callsign,
        content: reason ?? 'Request rejected.',
        profile: profile,
      );

      // Send rejection back
      final updatedLedger = await WalletService().findDebt(request.ledger.id);
      if (updatedLedger != null) {
        await sendAmendment(
          ledger: updatedLedger,
          targetCallsign: request.senderCallsign,
          profile: profile,
        );
      }
    }

    await _deleteRequest(requestId);
    return true;
  }

  /// Delete a request
  Future<bool> deleteRequest(String requestId) async {
    return _deleteRequest(requestId);
  }

  // ============ Internal Methods ============

  Future<void> _saveRequest(WalletSyncRequest request) async {
    if (_basePath == null) return;

    try {
      final file = File(path.join(_basePath!, 'requests', '${request.id}.json'));
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(request.toJson()));
    } catch (e) {
      LogService().log('WalletSyncService: Error saving request: $e');
    }
  }

  Future<bool> _deleteRequest(String requestId) async {
    if (_basePath == null) return false;

    try {
      final file = File(path.join(_basePath!, 'requests', '$requestId.json'));
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      LogService().log('WalletSyncService: Error deleting request: $e');
      return false;
    }
  }

  Future<int> _countPendingFromSender(String callsign) async {
    final requests = await getPendingRequests();
    return requests.where((r) => r.senderCallsign == callsign).length;
  }

  /// Save incoming ledger to local wallet (for new debts from counterparty)
  Future<bool> _saveLedgerToLocalWallet(DebtLedger incomingLedger) async {
    final walletPath = WalletService().currentPath;
    if (walletPath == null) {
      LogService().log('WalletSyncService: WalletService not initialized');
      return false;
    }

    try {
      // Set the file path for the new debt
      incomingLedger.filePath = path.join(walletPath, 'debts', '${incomingLedger.id}.md');

      // Save the ledger file
      final file = File(incomingLedger.filePath!);
      await file.parent.create(recursive: true);
      await file.writeAsString(incomingLedger.export());

      LogService().log('WalletSyncService: Saved incoming ledger ${incomingLedger.id} to local wallet');
      return true;
    } catch (e) {
      LogService().log('WalletSyncService: Error saving incoming ledger: $e');
      return false;
    }
  }

  /// Merge incoming ledger with local copy
  Future<bool> _mergeLedger(DebtLedger incomingLedger) async {
    // Find local copy
    var localLedger = await WalletService().findDebt(incomingLedger.id);

    if (localLedger == null) {
      // No local copy, save incoming as new
      localLedger = incomingLedger;
      localLedger.filePath = path.join(
        WalletService().currentPath ?? '',
        'debts',
        '${incomingLedger.id}.md',
      );
    } else {
      // Merge entries (add any that are not already present)
      for (final entry in incomingLedger.entries) {
        final exists = localLedger.entries.any((e) =>
            e.author == entry.author &&
            e.timestamp == entry.timestamp &&
            e.type == entry.type);
        if (!exists) {
          localLedger.addEntry(entry);
        }
      }
    }

    // Verify all signatures
    await WalletService().verifyDebt(localLedger);

    // Save updated ledger
    // Note: We need direct file access here since WalletService._saveLedger is private
    try {
      final file = File(localLedger.filePath!);
      await file.parent.create(recursive: true);
      await file.writeAsString(localLedger.export());
      return true;
    } catch (e) {
      LogService().log('WalletSyncService: Error saving merged ledger: $e');
      return false;
    }
  }

  String _generateRequestId() {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final random = now.microsecondsSinceEpoch.toRadixString(36).substring(0, 6);
    return 'req_${dateStr}_$random';
  }

  /// Receive sync data from HTTP API
  /// Returns result map with success/error status
  Future<Map<String, dynamic>> receiveSyncData(Map<String, dynamic> data) async {
    if (_basePath == null) {
      return {'success': false, 'error': 'Wallet sync not initialized'};
    }

    try {
      final typeStr = data['type'] as String? ?? 'debt_approval';
      final type = WalletRequestType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => WalletRequestType.debtApproval,
      );

      final ledgerContent = data['ledger'] as String?;
      if (ledgerContent == null) {
        return {'success': false, 'error': 'Missing ledger data'};
      }

      final ledger = DebtLedger.parse(ledgerContent);

      final senderCallsign = data['sender_callsign'] as String? ?? 'UNKNOWN';
      final senderNpub = data['sender_npub'] as String? ?? '';

      // For amendment approvals, auto-merge without creating a pending request
      // This is when the counterparty sends back their signed version
      if (type == WalletRequestType.amendmentApproval) {
        final merged = await _mergeLedger(ledger);
        LogService().log('WalletSyncService: Auto-merged amendment from $senderCallsign: $merged');
        return {
          'success': merged,
          'type': type.name,
          'debt_id': ledger.id,
          'auto_merged': true,
        };
      }

      // Check rate limiting for requests that need approval
      final pendingCount = await _countPendingFromSender(senderCallsign);
      if (pendingCount >= maxPendingPerSender) {
        return {'success': false, 'error': 'Rate limit exceeded for sender'};
      }

      // Create request for types that need explicit approval
      final request = WalletSyncRequest(
        id: _generateRequestId(),
        type: type,
        ledger: ledger,
        senderCallsign: senderCallsign,
        senderNpub: senderNpub,
        receivedAt: DateTime.now(),
      );

      // Save to disk
      await _saveRequest(request);

      // Notify listeners
      _requestsController.add(request);

      LogService().log('WalletSyncService: Received sync data ${request.id} from ${request.senderCallsign}');

      return {
        'success': true,
        'request_id': request.id,
        'type': type.name,
        'debt_id': ledger.id,
      };
    } catch (e) {
      LogService().log('WalletSyncService: Error processing sync data: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
