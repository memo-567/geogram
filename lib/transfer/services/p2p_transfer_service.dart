import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../connection/connection_manager.dart';
import '../../connection/transport_message.dart';
import '../../services/devices_service.dart';
import '../../services/log_service.dart';
import '../../services/profile_service.dart';
import '../../util/event_bus.dart';
import '../../util/nostr_event.dart';
import '../models/transfer_offer.dart';
import '../models/transfer_models.dart';
import '../../pages/transfer_send_page.dart';
import 'transfer_metrics_service.dart';
import 'transfer_service.dart';

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

    // Check/refresh device reachability before sending
    final isReachable =
        await DevicesService().checkReachability(recipientCallsign);
    if (!isReachable) {
      LogService().log(
        'P2PTransfer: Device $recipientCallsign is not reachable',
      );
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

    // Send offer with retry logic
    const maxRetries = 5;
    const baseDelay = Duration(seconds: 2);
    int retryCount = 0;
    TransportResult? result;

    while (retryCount <= maxRetries) {
      result = await ConnectionManager().apiRequest(
        callsign: recipientCallsign,
        method: 'POST',
        path: '/api/p2p/offer',
        body: offer.toOfferMessage(),
      );

      if (result.success) {
        LogService().log('P2PTransfer: Offer $offerId delivered to $recipientCallsign');
        break;
      }

      retryCount++;
      if (retryCount <= maxRetries) {
        final delay = baseDelay * retryCount; // Linear backoff
        LogService().log('P2PTransfer: Offer delivery failed, retry $retryCount/$maxRetries in ${delay.inSeconds}s');
        await Future.delayed(delay);
      }
    }

    if (result == null || !result.success) {
      LogService().log('P2PTransfer: Failed to send offer after $maxRetries retries: ${result?.error}');
      offer.status = TransferOfferStatus.failed;
      offer.error = result?.error ?? 'Delivery failed after $maxRetries retries';
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
      offer.startedAt = DateTime.now();
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

      // Record to metrics service (sender side - upload)
      TransferMetricsService().recordP2PTransferComplete(
        callsign: offer.receiverCallsign ?? 'Unknown',
        bytesTransferred: offer.bytesTransferred,
        isUpload: true, // We are uploading/sending
      );

      // Archive each file as a Transfer record for history
      for (final fileInfo in offer.files) {
        final transfer = Transfer(
          id: '${offer.offerId}_${fileInfo.name.hashCode}',
          direction: TransferDirection.upload,
          sourceCallsign: '',
          targetCallsign: offer.receiverCallsign ?? 'Unknown',
          remotePath: fileInfo.name,
          localPath: fileInfo.path,
          filename: fileInfo.name,
          expectedBytes: fileInfo.size,
          status: TransferStatus.completed,
          bytesTransferred: fileInfo.size,
          createdAt: offer.startedAt ?? offer.createdAt,
          completedAt: DateTime.now(),
          transportUsed: 'p2p',
        );
        TransferService().archiveCompletedTransfer(transfer);
      }
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

  /// Update upload progress (called from LogApiService during file streaming)
  void updateUploadProgress(String offerId, int bytesSent) {
    final offer = _outgoingOffers[offerId];
    if (offer == null) return;

    offer.status = TransferOfferStatus.transferring;
    offer.bytesTransferred += bytesSent;

    // Fire event every 256KB
    if (offer.bytesTransferred % 262144 < bytesSent) {
      _eventBus.fire(P2PUploadProgressEvent(
        offerId: offerId,
        bytesTransferred: offer.bytesTransferred,
        totalBytes: offer.totalBytes,
        filesCompleted: offer.filesCompleted,
        totalFiles: offer.totalFiles,
      ));
    }
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
    offer.startedAt = DateTime.now();

    // Send acceptance response
    await _sendResponse(offer, true);

    // Fire status change
    _eventBus.fire(TransferOfferStatusChangedEvent(
      offerId: offerId,
      status: 'accepted',
    ));

    // Start download in background (don't await - let UI navigate first)
    _startDownload(offer);
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

  /// Send accept/reject response to sender via direct API call
  Future<void> _sendResponse(TransferOffer offer, bool accepted) async {
    final profile = ProfileService().getProfile();
    final endpoint = accepted
        ? '/api/p2p/offer/${offer.offerId}/accept'
        : '/api/p2p/offer/${offer.offerId}/reject';

    // Send response with retry
    const maxRetries = 3;
    int retryCount = 0;
    TransportResult? result;

    while (retryCount <= maxRetries) {
      result = await ConnectionManager().apiRequest(
        callsign: offer.senderCallsign,
        method: 'POST',
        path: endpoint,
        body: {
          'receiverCallsign': profile.callsign,
        },
      );

      if (result.success) break;

      retryCount++;
      if (retryCount <= maxRetries) {
        await Future.delayed(Duration(seconds: retryCount));
      }
    }

    if (result == null || !result.success) {
      LogService().log('P2PTransfer: Failed to send response after $maxRetries retries: ${result?.error}');
    } else {
      LogService().log('P2PTransfer: Response sent to ${offer.senderCallsign}');
    }
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

        // Download with retry on SHA1 mismatch
        const maxRetries = 3;
        int retries = 0;
        bool sha1Verified = false;

        while (retries < maxRetries && !sha1Verified) {
          // Write to file
          final sink = destFile.openWrite();

          // Need to re-request for retries
          final retryRequest = http.Request('GET', fileUrl);
          final retryResponse = retries == 0
              ? streamedResponse
              : await retryRequest.send();

          if (retryResponse.statusCode != 200) {
            throw Exception('Failed to download ${file.path}: ${retryResponse.statusCode}');
          }

          // Track bytes for this attempt (subtract previous attempt's bytes)
          if (retries > 0) {
            totalBytesReceived -= file.size;
          }

          await for (final chunk in retryResponse.stream) {
            sink.add(chunk);
            totalBytesReceived += chunk.length;

            // Update offer progress locally during streaming
            offer.bytesTransferred = totalBytesReceived;

            // Fire local progress event every 256KB
            if (totalBytesReceived % 262144 < chunk.length) {
              _eventBus.fire(P2PDownloadProgressEvent(
                offerId: offer.offerId,
                bytesTransferred: totalBytesReceived,
                totalBytes: offer.totalBytes,
              ));
            }
          }

          await sink.close();

          // Verify SHA1 if provided
          if (file.sha1 != null) {
            final bytes = await destFile.readAsBytes();
            final hash = sha1.convert(bytes).toString();
            if (hash == file.sha1) {
              sha1Verified = true;
            } else {
              retries++;
              if (retries >= maxRetries) {
                throw Exception('SHA1 mismatch for ${file.path} after $maxRetries retries');
              }
              LogService().log('P2PTransfer: SHA1 mismatch for ${file.path}, retry $retries/$maxRetries');
            }
          } else {
            sha1Verified = true;
          }
        }

        filesCompleted++;
        offer.filesCompleted = filesCompleted;
        offer.bytesTransferred = totalBytesReceived;

        LogService().log('P2PTransfer: Downloaded ${file.path} (${file.size} bytes)');
      }

      // All files downloaded successfully
      offer.status = TransferOfferStatus.completed;

      // Record to metrics service (receiver side - download)
      TransferMetricsService().recordP2PTransferComplete(
        callsign: offer.senderCallsign,
        bytesTransferred: totalBytesReceived,
        isUpload: false, // We are downloading/receiving
      );

      // Archive each file as a Transfer record for history
      for (final fileInfo in offer.files) {
        final transfer = Transfer(
          id: '${offer.offerId}_${fileInfo.name.hashCode}',
          direction: TransferDirection.download,
          sourceCallsign: offer.senderCallsign,
          targetCallsign: '',
          remotePath: fileInfo.name,
          localPath: '${offer.destinationPath}/${fileInfo.path}',
          filename: fileInfo.name,
          expectedBytes: fileInfo.size,
          status: TransferStatus.completed,
          bytesTransferred: fileInfo.size,
          createdAt: offer.startedAt ?? offer.createdAt,
          completedAt: DateTime.now(),
          transportUsed: 'p2p',
        );
        TransferService().archiveCompletedTransfer(transfer);
      }

      // Send completion notification
      await _sendCompletion(offer, true, totalBytesReceived, filesCompleted);

      // Fire completion event for receiver UI
      _eventBus.fire(P2PTransferCompleteEvent(
        offerId: offer.offerId,
        success: true,
        bytesReceived: totalBytesReceived,
        filesReceived: filesCompleted,
      ));

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

      // Fire completion event for receiver UI
      _eventBus.fire(P2PTransferCompleteEvent(
        offerId: offer.offerId,
        success: false,
        bytesReceived: totalBytesReceived,
        filesReceived: filesCompleted,
        error: e.toString(),
      ));

      _eventBus.fire(TransferOfferStatusChangedEvent(
        offerId: offer.offerId,
        status: 'failed',
        error: e.toString(),
      ));
    }
  }

  /// Get the API URL for a sender
  Future<String?> _getSenderApiUrl(String callsign) async {
    final device = DevicesService().getDevice(callsign);
    if (device?.url != null) {
      return device!.url;
    }
    LogService().log('P2PTransfer: No URL found for sender $callsign');
    return null;
  }

  /// Send completion notification to sender via direct API call
  Future<void> _sendCompletion(
    TransferOffer offer,
    bool success,
    int bytesReceived,
    int filesReceived, {
    String? error,
  }) async {
    final endpoint = '/api/p2p/offer/${offer.offerId}/complete';

    // Send completion with retry
    const maxRetries = 3;
    int retryCount = 0;
    TransportResult? result;

    while (retryCount <= maxRetries) {
      result = await ConnectionManager().apiRequest(
        callsign: offer.senderCallsign,
        method: 'POST',
        path: endpoint,
        body: {
          'success': success,
          'bytesReceived': bytesReceived,
          'filesReceived': filesReceived,
          if (error != null) 'error': error,
        },
      );

      if (result.success) break;

      retryCount++;
      if (retryCount <= maxRetries) {
        await Future.delayed(Duration(seconds: retryCount));
      }
    }

    if (result == null || !result.success) {
      LogService().log('P2PTransfer: Failed to send completion after $maxRetries retries: ${result?.error}');
    } else {
      LogService().log('P2PTransfer: Completion sent to ${offer.senderCallsign}');
    }
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
