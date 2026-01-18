/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Chat File Upload Manager - Tracks file uploads (when serving files to receivers)
 * Handles progress tracking, retry capability, and auto-resume on reconnection.
 */

import 'dart:async';
import '../util/event_bus.dart';
import 'devices_service.dart';
import 'log_service.dart';

/// Upload state
enum ChatUploadStatus {
  pending,     // Waiting for receiver to request
  uploading,   // Transfer in progress
  completed,   // Finished successfully
  failed,      // Failed (can retry)
}

/// Upload entry representing a file being served to a receiver
class ChatUpload {
  final String id;              // Unique identifier (receiverCallsign_filename)
  final String messageId;       // Message ID this upload belongs to
  final String receiverCallsign;
  final String filename;
  final int totalBytes;
  int bytesTransferred = 0;
  ChatUploadStatus status = ChatUploadStatus.pending;
  String? error;
  double? speedBytesPerSecond;
  DateTime? startTime;
  DateTime? lastUpdateTime;
  int retryCount = 0;

  ChatUpload({
    required this.id,
    required this.messageId,
    required this.receiverCallsign,
    required this.filename,
    required this.totalBytes,
  });

  double get progressPercent =>
      totalBytes > 0 ? (bytesTransferred / totalBytes * 100) : 0;

  /// Human-readable file size
  String get fileSizeFormatted => _formatBytes(totalBytes);

  /// Human-readable bytes transferred
  String get bytesTransferredFormatted => _formatBytes(bytesTransferred);

  /// Human-readable transfer speed
  String? get speedFormatted => speedBytesPerSecond != null
      ? '${_formatBytes(speedBytesPerSecond!.toInt())}/s'
      : null;

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ChatUpload copyWith({
    int? bytesTransferred,
    ChatUploadStatus? status,
    String? error,
    double? speedBytesPerSecond,
    DateTime? startTime,
    DateTime? lastUpdateTime,
    int? retryCount,
  }) {
    final copy = ChatUpload(
      id: id,
      messageId: messageId,
      receiverCallsign: receiverCallsign,
      filename: filename,
      totalBytes: totalBytes,
    );
    copy.bytesTransferred = bytesTransferred ?? this.bytesTransferred;
    copy.status = status ?? this.status;
    copy.error = error ?? this.error;
    copy.speedBytesPerSecond = speedBytesPerSecond ?? this.speedBytesPerSecond;
    copy.startTime = startTime ?? this.startTime;
    copy.lastUpdateTime = lastUpdateTime ?? this.lastUpdateTime;
    copy.retryCount = retryCount ?? this.retryCount;
    return copy;
  }
}

/// File upload manager for DM file transfers
/// Tracks when files are being served to receivers and handles retry/resume.
class ChatFileUploadManager {
  static final ChatFileUploadManager _instance = ChatFileUploadManager._internal();
  factory ChatFileUploadManager() => _instance;
  ChatFileUploadManager._internal();

  /// Active and pending uploads
  final Map<String, ChatUpload> _uploads = {};

  /// Stream controller for upload state changes
  final _uploadController = StreamController<ChatUpload>.broadcast();
  Stream<ChatUpload> get uploadStream => _uploadController.stream;

  /// Device reconnection subscription
  EventSubscription<DeviceStatusChangedEvent>? _deviceSubscription;

  /// Initialize manager and listen for device reconnections
  void initialize() {
    _deviceSubscription?.cancel();
    _deviceSubscription = EventBus().on<DeviceStatusChangedEvent>((event) {
      if (event.isReachable) {
        _onDeviceReconnected(event.callsign);
      }
    });
  }

  /// Generate unique upload ID
  String generateUploadId(String receiverCallsign, String filename) {
    return '${receiverCallsign.toUpperCase()}_$filename';
  }

  /// Register a pending upload when sending a file message
  /// Call this after successfully sending the message metadata
  void registerPendingUpload({
    required String messageId,
    required String receiverCallsign,
    required String filename,
    required int totalBytes,
  }) {
    final id = generateUploadId(receiverCallsign, filename);

    // Don't overwrite if already tracking this upload
    if (_uploads.containsKey(id)) {
      LogService().log('ChatFileUploadManager: Upload already registered: $id');
      return;
    }

    final upload = ChatUpload(
      id: id,
      messageId: messageId,
      receiverCallsign: receiverCallsign.toUpperCase(),
      filename: filename,
      totalBytes: totalBytes,
    );
    upload.status = ChatUploadStatus.pending;
    _uploads[id] = upload;
    _notifyUploadChanged(upload);

    LogService().log('ChatFileUploadManager: Registered pending upload: $id (${upload.fileSizeFormatted})');
  }

  /// Start tracking an upload (called when receiver requests the file)
  void startUpload(String receiverCallsign, String filename, int totalBytes) {
    final id = generateUploadId(receiverCallsign, filename);

    var upload = _uploads[id];
    if (upload == null) {
      // Create new upload entry if not pre-registered
      upload = ChatUpload(
        id: id,
        messageId: '', // Unknown - not pre-registered
        receiverCallsign: receiverCallsign.toUpperCase(),
        filename: filename,
        totalBytes: totalBytes,
      );
    }

    upload.status = ChatUploadStatus.uploading;
    upload.startTime = DateTime.now();
    upload.bytesTransferred = 0;
    _uploads[id] = upload;
    _notifyUploadChanged(upload);

    LogService().log('ChatFileUploadManager: Started upload: $id');
  }

  /// Update upload progress (called as bytes are sent)
  void updateProgress(String receiverCallsign, String filename, int bytesSent) {
    final id = generateUploadId(receiverCallsign, filename);
    final upload = _uploads[id];
    if (upload == null) return;

    final now = DateTime.now();

    // Calculate speed
    if (upload.lastUpdateTime != null) {
      final elapsed = now.difference(upload.lastUpdateTime!).inMilliseconds;
      if (elapsed > 0) {
        final bytesDiff = bytesSent - upload.bytesTransferred;
        upload.speedBytesPerSecond = (bytesDiff / elapsed) * 1000;
      }
    }

    upload.bytesTransferred = bytesSent;
    upload.lastUpdateTime = now;
    _uploads[id] = upload;
    _notifyUploadChanged(upload);
  }

  /// Mark upload as completed
  void completeUpload(String receiverCallsign, String filename) {
    final id = generateUploadId(receiverCallsign, filename);
    final upload = _uploads[id];
    if (upload == null) return;

    upload.status = ChatUploadStatus.completed;
    upload.bytesTransferred = upload.totalBytes;
    upload.lastUpdateTime = DateTime.now();
    _uploads[id] = upload;
    _notifyUploadChanged(upload);

    LogService().log('ChatFileUploadManager: Upload completed: $id');
  }

  /// Mark upload as failed
  void failUpload(String receiverCallsign, String filename, String error) {
    final id = generateUploadId(receiverCallsign, filename);
    var upload = _uploads[id];

    if (upload == null) {
      // Create entry if not tracked
      upload = ChatUpload(
        id: id,
        messageId: '',
        receiverCallsign: receiverCallsign.toUpperCase(),
        filename: filename,
        totalBytes: 0,
      );
    }

    upload.status = ChatUploadStatus.failed;
    upload.error = error;
    upload.lastUpdateTime = DateTime.now();
    _uploads[id] = upload;
    _notifyUploadChanged(upload);

    LogService().log('ChatFileUploadManager: Upload failed: $id - $error');
  }

  /// Get upload state by ID
  ChatUpload? getUpload(String id) => _uploads[id];

  /// Get upload for a specific file
  ChatUpload? getUploadForFile(String receiverCallsign, String filename) {
    final id = generateUploadId(receiverCallsign, filename);
    return _uploads[id];
  }

  /// Get all uploads for a receiver
  List<ChatUpload> getUploadsForReceiver(String receiverCallsign) {
    return _uploads.values
        .where((u) => u.receiverCallsign == receiverCallsign.toUpperCase())
        .toList();
  }

  /// Get all pending/failed uploads (for retry)
  List<ChatUpload> getPendingUploads(String receiverCallsign) {
    return _uploads.values
        .where((u) =>
            u.receiverCallsign == receiverCallsign.toUpperCase() &&
            (u.status == ChatUploadStatus.pending ||
             u.status == ChatUploadStatus.failed))
        .toList();
  }

  /// Check if upload is in progress
  bool isUploading(String id) {
    final upload = _uploads[id];
    return upload != null && upload.status == ChatUploadStatus.uploading;
  }

  /// Request retry - sends a notification to receiver to re-request the file
  /// Returns true if notification was sent successfully
  Future<bool> requestRetry(String receiverCallsign, String filename) async {
    final id = generateUploadId(receiverCallsign, filename);
    final upload = _uploads[id];
    if (upload == null) return false;

    // Check if device is reachable
    final device = DevicesService().getDevice(receiverCallsign.toUpperCase());
    if (device == null || !device.isOnline) {
      LogService().log('ChatFileUploadManager: Cannot retry - device not reachable: $receiverCallsign');
      return false;
    }

    // Mark as pending again
    upload.status = ChatUploadStatus.pending;
    upload.retryCount++;
    upload.error = null;
    _uploads[id] = upload;
    _notifyUploadChanged(upload);

    // Send a nudge to the receiver to re-request the file
    // This is done by sending a lightweight "file_available" notification
    try {
      await DevicesService().makeDeviceApiRequest(
        callsign: receiverCallsign,
        method: 'POST',
        path: '/api/dm/file_available',
        headers: {'Content-Type': 'application/json'},
        body: '{"filename": "$filename"}',
      );
      LogService().log('ChatFileUploadManager: Sent retry notification for: $id');
      return true;
    } catch (e) {
      LogService().log('ChatFileUploadManager: Failed to send retry notification: $e');
      return false;
    }
  }

  /// Handle device reconnection - check for pending uploads
  void _onDeviceReconnected(String callsign) {
    final pendingUploads = getPendingUploads(callsign);
    if (pendingUploads.isEmpty) return;

    LogService().log('ChatFileUploadManager: Device reconnected with ${pendingUploads.length} pending uploads: $callsign');

    // Fire event to notify UI about pending uploads
    for (final upload in pendingUploads) {
      _notifyUploadChanged(upload);
    }

    // Auto-retry failed uploads
    for (final upload in pendingUploads.where((u) => u.status == ChatUploadStatus.failed)) {
      requestRetry(upload.receiverCallsign, upload.filename);
    }
  }

  /// Clear completed uploads older than the specified duration
  void clearOldUploads({Duration maxAge = const Duration(hours: 1)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    final toRemove = <String>[];

    for (final entry in _uploads.entries) {
      final upload = entry.value;
      if (upload.status == ChatUploadStatus.completed &&
          upload.lastUpdateTime != null &&
          upload.lastUpdateTime!.isBefore(cutoff)) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _uploads.remove(id);
    }
  }

  /// Notify listeners of upload state change
  void _notifyUploadChanged(ChatUpload upload) {
    if (!_uploadController.isClosed) {
      _uploadController.add(upload);
    }

    // Fire event bus event for cross-widget updates
    EventBus().fire(ChatUploadProgressEvent(
      uploadId: upload.id,
      messageId: upload.messageId,
      receiverCallsign: upload.receiverCallsign,
      filename: upload.filename,
      bytesTransferred: upload.bytesTransferred,
      totalBytes: upload.totalBytes,
      speedBytesPerSecond: upload.speedBytesPerSecond,
      status: upload.status,
      error: upload.error,
    ));
  }

  /// Dispose resources
  void dispose() {
    _deviceSubscription?.cancel();
    _uploadController.close();
  }
}
