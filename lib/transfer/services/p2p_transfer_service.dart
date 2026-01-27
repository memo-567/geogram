import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../connection/connection_manager.dart';
import '../../services/log_service.dart';
import '../../services/log_api_service.dart';
import '../../services/profile_service.dart';
import '../../services/signing_service.dart';
import '../../util/event_bus.dart';
import '../../util/nostr_event.dart';
import '../models/transfer_offer.dart';
import '../../pages/transfer_send_page.dart';

/// P2P Transfer Service - Manages peer-to-peer file transfers
///
/// Flow:
/// 1. Sender: sendOffer() creates offer and sends via DM
/// 2. Receiver: handleIncomingOffer() processes offer, fires event
/// 3. Receiver: acceptOffer() or rejectOffer() sends response
/// 4. Receiver: startDownload() fetches files from sender's API
/// 5. Sender: receives progress updates and completion notification
class P2PTransferService {
  static final P2PTransferService _instance = P2PTransferService._internal();
  factory P2PTransferService() => _instance;
  P2PTransferService._internal();

  final EventBus _eventBus = EventBus();
  final Map<String, TransferOffer> _outgoingOffers = {};
  final Map<String, TransferOffer> _incomingOffers = {};

  // Token to offer ID mapping for file serving
  final Map<String, String> _serveTokens = {};

  // Default offer expiry duration
  static const Duration _offerExpiry = Duration(hours: 1);

  /// Get all outgoing (sent) offers
  List<TransferOffer> get outgoingOffers => _outgoingOffers.values.toList();

  /// Get all incoming (received) offers
  List<TransferOffer> get incomingOffers => _incomingOffers.values.toList();

  /// Get an offer by ID
  TransferOffer? getOffer(String offerId) {
    return _outgoingOffers[offerId] ?? _incomingOffers[offerId];
  }

  // ============================================================
  // Sender Side
  // ============================================================

  /// Send a transfer offer to a recipient
  ///
  /// Creates an offer with the selected files and sends it via DM.
  Future<TransferOffer?> sendOffer({
    required String recipientCallsign,
    required List<SendItem> items,
  }) async {
    final profile = ProfileService().getProfile();
    if (profile.callsign.isEmpty) {
      LogService().log('P2PTransfer: No active profile');
      return null;
    }

    // Build file list with SHA1 hashes
    final files = <TransferOfferFile>[];
    int totalBytes = 0;

    for (final item in items) {
      if (item.isDirectory) {
        // Add all files from directory
        await _addDirectoryFiles(files, item.path, item.name);
      } else {
        // Add single file
        final file = File(item.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final sha1Hash = sha1.convert(bytes).toString();
          files.add(TransferOfferFile(
            path: item.name,
            name: item.name,
            size: bytes.length,
            sha1: sha1Hash,
          ));
        }
      }
    }

    // Calculate total bytes
    for (final f in files) {
      totalBytes += f.size;
    }

    if (files.isEmpty) {
      LogService().log('P2PTransfer: No files to send');
      return null;
    }

    // Generate offer ID and serve token
    final offerId = TransferOffer.generateOfferId();
    final serveToken = _generateToken();

    // Create offer
    final now = DateTime.now();
    final offer = TransferOffer(
      offerId: offerId,
      senderCallsign: profile.callsign,
      senderNpub: profile.npub,
      receiverCallsign: recipientCallsign,
      createdAt: now,
      expiresAt: now.add(_offerExpiry),
      files: files,
      totalBytes: totalBytes,
      status: TransferOfferStatus.pending,
      serveToken: serveToken,
    );

    // Store offer and token
    _outgoingOffers[offerId] = offer;
    _serveTokens[serveToken] = offerId;

    // Register files for serving
    _registerFilesForServing(offer, items);

    // Create signed NOSTR event with offer message
    final content = jsonEncode(offer.toOfferMessage());
    final event = NostrEvent(
      pubkey: profile.npub,
      kind: 4, // Encrypted DM
      content: content,
      tags: [
        ['p', recipientCallsign], // Target callsign as tag
        ['t', 'transfer_offer'],
      ],
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
    );

    // Sign the event
    final signedEvent = await SigningService().signEvent(event, profile);
    if (signedEvent == null) {
      LogService().log('P2PTransfer: Failed to sign offer event');
      _outgoingOffers.remove(offerId);
      _serveTokens.remove(serveToken);
      return null;
    }

    // Send via ConnectionManager
    final result = await ConnectionManager().sendDM(
      callsign: recipientCallsign,
      signedEvent: signedEvent.toJson(),
      ttl: _offerExpiry,
    );

    if (!result.success && !result.wasQueued) {
      LogService().log('P2PTransfer: Failed to send offer: ${result.error}');
      offer.status = TransferOfferStatus.failed;
      offer.error = result.error;
    } else {
      LogService().log('P2PTransfer: Offer $offerId sent to $recipientCallsign');
    }

    // Fire status change event
    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: offer.status.name,
      error: offer.error,
    ));

    return offer;
  }

  /// Cancel an outgoing offer
  Future<void> cancelOffer(String offerId) async {
    final offer = _outgoingOffers[offerId];
    if (offer == null) return;

    offer.status = TransferOfferStatus.cancelled;

    // Clean up token
    if (offer.serveToken != null) {
      _serveTokens.remove(offer.serveToken);
    }

    // Fire event
    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: 'cancelled',
    ));

    LogService().log('P2PTransfer: Cancelled offer $offerId');
  }

  /// Handle response from receiver
  void handleTransferResponse(Map<String, dynamic> message) {
    final offerId = message['offerId'] as String?;
    final accepted = message['accepted'] as bool? ?? false;
    final receiverCallsign = message['receiverCallsign'] as String?;

    if (offerId == null) return;

    final offer = _outgoingOffers[offerId];
    if (offer == null) {
      LogService().log('P2PTransfer: Unknown offer response: $offerId');
      return;
    }

    if (accepted) {
      offer.status = TransferOfferStatus.accepted;
      offer.receiverCallsign = receiverCallsign;
      LogService().log('P2PTransfer: Offer $offerId accepted by $receiverCallsign');
    } else {
      offer.status = TransferOfferStatus.rejected;
      // Clean up token
      if (offer.serveToken != null) {
        _serveTokens.remove(offer.serveToken);
      }
      LogService().log('P2PTransfer: Offer $offerId rejected by $receiverCallsign');
    }

    // Fire event
    _eventBus.fire(TransferOfferResponseEvent(
      offerId: offerId,
      accepted: accepted,
      receiverCallsign: receiverCallsign ?? '',
    ));

    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: offer.status.name,
    ));
  }

  /// Handle progress update from receiver
  void handleProgressUpdate(Map<String, dynamic> message) {
    final offerId = message['offerId'] as String?;
    if (offerId == null) return;

    final offer = _outgoingOffers[offerId];
    if (offer == null) return;

    offer.status = TransferOfferStatus.transferring;
    offer.bytesTransferred = message['bytesReceived'] as int? ?? 0;
    offer.filesCompleted = message['filesCompleted'] as int? ?? 0;
    offer.currentFile = message['currentFile'] as String?;

    // Fire progress event
    _eventBus.fire(P2PUploadProgressEvent(
      offerId: offerId,
      bytesTransferred: offer.bytesTransferred,
      totalBytes: offer.totalBytes,
      filesCompleted: offer.filesCompleted,
      totalFiles: offer.totalFiles,
      currentFile: offer.currentFile,
    ));
  }

  /// Handle completion notification from receiver
  void handleTransferComplete(Map<String, dynamic> message) {
    final offerId = message['offerId'] as String?;
    if (offerId == null) return;

    final offer = _outgoingOffers[offerId];
    if (offer == null) return;

    final success = message['success'] as bool? ?? false;
    offer.bytesTransferred = message['bytesReceived'] as int? ?? 0;
    offer.filesCompleted = message['filesReceived'] as int? ?? 0;

    if (success) {
      offer.status = TransferOfferStatus.completed;
      LogService().log('P2PTransfer: Offer $offerId completed successfully');
    } else {
      offer.status = TransferOfferStatus.failed;
      offer.error = message['error'] as String?;
      LogService().log('P2PTransfer: Offer $offerId failed: ${offer.error}');
    }

    // Clean up token
    if (offer.serveToken != null) {
      _serveTokens.remove(offer.serveToken);
    }

    // Fire events
    _eventBus.fire(P2PTransferCompleteEvent(
      offerId: offerId,
      success: success,
      bytesReceived: offer.bytesTransferred,
      filesReceived: offer.filesCompleted,
      error: offer.error,
    ));

    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: offer.status.name,
      error: offer.error,
    ));
  }

  // ============================================================
  // Receiver Side
  // ============================================================

  /// Handle incoming transfer offer
  void handleIncomingOffer(Map<String, dynamic> message) {
    try {
      final offer = TransferOffer.fromOfferMessage(message);

      // Check if already expired
      if (offer.isExpired) {
        LogService().log('P2PTransfer: Ignoring expired offer ${offer.offerId}');
        return;
      }

      // Store offer
      _incomingOffers[offer.offerId] = offer;

      // Fire event for UI
      _eventBus.fire(TransferOfferReceivedEvent(
        offerId: offer.offerId,
        senderCallsign: offer.senderCallsign,
        senderNpub: offer.senderNpub,
        totalFiles: offer.totalFiles,
        totalBytes: offer.totalBytes,
        expiresAt: offer.expiresAt,
        files: offer.files.map((f) => f.toJson()).toList(),
      ));

      LogService().log(
        'P2PTransfer: Received offer ${offer.offerId} from ${offer.senderCallsign} '
        '(${offer.totalFiles} files, ${offer.totalBytes} bytes)',
      );
    } catch (e) {
      LogService().log('P2PTransfer: Error parsing incoming offer: $e');
    }
  }

  /// Accept an incoming offer and start download
  Future<void> acceptOffer(String offerId, String destinationPath) async {
    final offer = _incomingOffers[offerId];
    if (offer == null) {
      LogService().log('P2PTransfer: Unknown offer: $offerId');
      return;
    }

    if (offer.isExpired) {
      offer.status = TransferOfferStatus.expired;
      _eventBus.fire(TransferOfferStatusChangedEvent(
        offerId: offerId,
        status: 'expired',
      ));
      return;
    }

    final profile = ProfileService().getProfile();
    if (profile.callsign.isEmpty) return;

    offer.status = TransferOfferStatus.accepted;
    offer.destinationPath = destinationPath;

    // Send acceptance response
    await _sendResponse(offer, true);

    // Fire status change
    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: 'accepted',
    ));

    // Start download
    await _startDownload(offer);
  }

  /// Reject an incoming offer
  Future<void> rejectOffer(String offerId) async {
    final offer = _incomingOffers[offerId];
    if (offer == null) return;

    offer.status = TransferOfferStatus.rejected;

    // Send rejection response
    await _sendResponse(offer, false);

    // Fire status change
    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: 'rejected',
    ));

    LogService().log('P2PTransfer: Rejected offer $offerId');
  }

  /// Send accept/reject response to sender
  Future<void> _sendResponse(TransferOffer offer, bool accepted) async {
    final profile = ProfileService().getProfile();
    if (profile.callsign.isEmpty) return;

    final responseData = TransferOffer.createResponse(
      offerId: offer.offerId,
      accepted: accepted,
      receiverCallsign: profile.callsign,
    );

    final event = NostrEvent(
      pubkey: profile.npub,
      kind: 4,
      content: jsonEncode(responseData),
      tags: [
        ['p', offer.senderCallsign],
        ['t', 'transfer_response'],
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final signedEvent = await SigningService().signEvent(event, profile);
    if (signedEvent == null) return;

    await ConnectionManager().sendDM(
      callsign: offer.senderCallsign,
      signedEvent: signedEvent.toJson(),
    );
  }

  /// Start downloading files from sender
  Future<void> _startDownload(TransferOffer offer) async {
    offer.status = TransferOfferStatus.transferring;

    final destDir = Directory(offer.destinationPath!);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    int totalBytesReceived = 0;
    int filesCompleted = 0;

    try {
      // Get sender's API URL
      final senderUrl = await _getSenderApiUrl(offer.senderCallsign);
      if (senderUrl == null) {
        throw Exception('Cannot reach sender ${offer.senderCallsign}');
      }

      // First, fetch manifest to get the serve token
      final manifestUrl = Uri.parse(
        '$senderUrl/api/p2p/offer/${offer.offerId}/manifest',
      );

      final manifestResponse = await http.get(manifestUrl).timeout(
        const Duration(seconds: 30),
      );

      if (manifestResponse.statusCode != 200) {
        throw Exception('Failed to get manifest: ${manifestResponse.statusCode}');
      }

      final manifestData = jsonDecode(manifestResponse.body) as Map<String, dynamic>;
      final token = manifestData['token'] as String?;
      if (token == null) {
        throw Exception('No token in manifest response');
      }

      // Download each file
      for (final file in offer.files) {
        offer.currentFile = file.path;

        // Send progress update
        await _sendProgressUpdate(offer, totalBytesReceived, filesCompleted);

        // Download file
        final fileUrl = Uri.parse(
          '$senderUrl/api/p2p/offer/${offer.offerId}/file'
          '?path=${Uri.encodeComponent(file.path)}&token=$token',
        );

        final destPath = path.join(offer.destinationPath!, file.path);
        final destFile = File(destPath);

        // Create parent directories
        await destFile.parent.create(recursive: true);

        // Download with streaming for large files
        final request = http.Request('GET', fileUrl);
        final streamedResponse = await request.send();

        if (streamedResponse.statusCode != 200) {
          throw Exception('Failed to download ${file.path}: ${streamedResponse.statusCode}');
        }

        // Write to file
        final sink = destFile.openWrite();
        int bytesReceived = 0;

        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          totalBytesReceived += chunk.length;

          // Send progress update periodically (every 64KB)
          if (bytesReceived % 65536 < chunk.length) {
            await _sendProgressUpdate(offer, totalBytesReceived, filesCompleted);
          }
        }

        await sink.close();

        // Verify SHA1 if provided
        if (file.sha1 != null) {
          final bytes = await destFile.readAsBytes();
          final hash = sha1.convert(bytes).toString();
          if (hash != file.sha1) {
            throw Exception('SHA1 mismatch for ${file.path}');
          }
        }

        filesCompleted++;
        offer.filesCompleted = filesCompleted;
        offer.bytesTransferred = totalBytesReceived;

        LogService().log('P2PTransfer: Downloaded ${file.path} ($bytesReceived bytes)');
      }

      // All files downloaded successfully
      offer.status = TransferOfferStatus.completed;

      // Send completion notification
      await _sendCompletion(offer, true, totalBytesReceived, filesCompleted);

      _eventBus.fire(TransferOfferStatusChangedEvent(
        offerId: offer.offerId,
        status: 'completed',
      ));

      LogService().log('P2PTransfer: Download complete - $filesCompleted files, $totalBytesReceived bytes');
    } catch (e) {
      LogService().log('P2PTransfer: Download failed: $e');
      offer.status = TransferOfferStatus.failed;
      offer.error = e.toString();

      // Send failure notification
      await _sendCompletion(
        offer,
        false,
        totalBytesReceived,
        filesCompleted,
        error: e.toString(),
      );

      _eventBus.fire(TransferOfferStatusChangedEvent(
        offerId: offer.offerId,
        status: 'failed',
        error: e.toString(),
      ));
    }
  }

  /// Get the API URL for a sender
  Future<String?> _getSenderApiUrl(String callsign) async {
    // Try to get URL from devices service or connection manager
    // For now, use the local port as fallback for testing
    final localPort = LogApiService().port;
    return 'http://localhost:$localPort';
  }

  /// Send progress update to sender
  Future<void> _sendProgressUpdate(
    TransferOffer offer,
    int bytesReceived,
    int filesCompleted,
  ) async {
    final profile = ProfileService().getProfile();
    if (profile.callsign.isEmpty) return;

    final progressData = TransferOffer.createProgressMessage(
      offerId: offer.offerId,
      bytesReceived: bytesReceived,
      totalBytes: offer.totalBytes,
      filesCompleted: filesCompleted,
      currentFile: offer.currentFile,
    );

    final event = NostrEvent(
      pubkey: profile.npub,
      kind: 4,
      content: jsonEncode(progressData),
      tags: [
        ['p', offer.senderCallsign],
        ['t', 'transfer_progress'],
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final signedEvent = await SigningService().signEvent(event, profile);
    if (signedEvent == null) return;

    // Send asynchronously, don't wait
    ConnectionManager().sendDM(
      callsign: offer.senderCallsign,
      signedEvent: signedEvent.toJson(),
    );
  }

  /// Send completion notification to sender
  Future<void> _sendCompletion(
    TransferOffer offer,
    bool success,
    int bytesReceived,
    int filesReceived, {
    String? error,
  }) async {
    final profile = ProfileService().getProfile();
    if (profile.callsign.isEmpty) return;

    final completeData = TransferOffer.createCompleteMessage(
      offerId: offer.offerId,
      success: success,
      bytesReceived: bytesReceived,
      filesReceived: filesReceived,
      error: error,
    );

    final event = NostrEvent(
      pubkey: profile.npub,
      kind: 4,
      content: jsonEncode(completeData),
      tags: [
        ['p', offer.senderCallsign],
        ['t', 'transfer_complete'],
      ],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final signedEvent = await SigningService().signEvent(event, profile);
    if (signedEvent == null) return;

    await ConnectionManager().sendDM(
      callsign: offer.senderCallsign,
      signedEvent: signedEvent.toJson(),
    );
  }

  // ============================================================
  // File Serving (Sender Side)
  // ============================================================

  /// File paths registered for serving (offerId -> path mapping)
  final Map<String, Map<String, String>> _registeredFiles = {};

  /// Register files for serving
  void _registerFilesForServing(TransferOffer offer, List<SendItem> items) {
    final pathMap = <String, String>{};

    for (final item in items) {
      if (item.isDirectory) {
        // Map all files in directory
        _mapDirectoryFiles(pathMap, item.path, item.name);
      } else {
        // Map single file
        pathMap[item.name] = item.path;
      }
    }

    _registeredFiles[offer.offerId] = pathMap;
    LogService().log('P2PTransfer: Registered ${pathMap.length} files for serving (offer ${offer.offerId})');
  }

  /// Map all files in a directory to their paths
  void _mapDirectoryFiles(Map<String, String> pathMap, String dirPath, String baseName) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: dirPath);
        final servePath = '$baseName/$relativePath';
        pathMap[servePath] = entity.path;
      }
    }
  }

  /// Validate a serve token and return the offer ID
  String? validateToken(String token) {
    return _serveTokens[token];
  }

  /// Get the manifest for an offer
  Map<String, dynamic>? getOfferManifest(String offerId) {
    final offer = _outgoingOffers[offerId];
    if (offer == null) return null;

    return {
      ...offer.toManifest(),
      'token': offer.serveToken,
    };
  }

  /// Get file path for serving
  String? getFilePath(String offerId, String filePath) {
    final pathMap = _registeredFiles[offerId];
    if (pathMap == null) return null;
    return pathMap[filePath];
  }

  // ============================================================
  // Helpers
  // ============================================================

  /// Add files from a directory to the file list
  Future<void> _addDirectoryFiles(
    List<TransferOfferFile> files,
    String dirPath,
    String baseName,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: dirPath);
        final servePath = '$baseName/$relativePath';
        final bytes = await entity.readAsBytes();
        final sha1Hash = sha1.convert(bytes).toString();

        files.add(TransferOfferFile(
          path: servePath,
          name: path.basename(entity.path),
          size: bytes.length,
          sha1: sha1Hash,
        ));
      }
    }
  }

  /// Generate a random token
  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Clean up expired offers
  void cleanupExpired() {
    _outgoingOffers.removeWhere((id, offer) {
      if (offer.isExpired && offer.status == TransferOfferStatus.pending) {
        offer.status = TransferOfferStatus.expired;
        if (offer.serveToken != null) {
          _serveTokens.remove(offer.serveToken);
        }
        _registeredFiles.remove(id);
        return true;
      }
      return false;
    });

    _incomingOffers.removeWhere((id, offer) {
      if (offer.isExpired && offer.status == TransferOfferStatus.pending) {
        offer.status = TransferOfferStatus.expired;
        return true;
      }
      return false;
    });
  }
}
