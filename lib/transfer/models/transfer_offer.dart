/// P2P Transfer offer status
enum TransferOfferStatus {
  pending,      // Offer created, waiting for response
  accepted,     // Receiver accepted, transfer starting
  rejected,     // Receiver declined
  expired,      // Offer expired before response
  cancelled,    // Sender cancelled
  transferring, // Files being transferred
  completed,    // All files transferred successfully
  failed,       // Transfer failed
}

/// Represents a file in a transfer offer
class TransferOfferFile {
  final String path;    // Relative path within the offer
  final String name;    // File name
  final int size;       // Size in bytes
  final String? sha1;   // SHA1 hash for verification

  const TransferOfferFile({
    required this.path,
    required this.name,
    required this.size,
    this.sha1,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    if (sha1 != null) 'sha1': sha1,
  };

  factory TransferOfferFile.fromJson(Map<String, dynamic> json) {
    return TransferOfferFile(
      path: json['path'] as String,
      name: json['name'] as String,
      size: json['size'] as int,
      sha1: json['sha1'] as String?,
    );
  }

  @override
  String toString() => 'TransferOfferFile(path: $path, size: $size)';
}

/// Represents a P2P transfer offer
///
/// Flow:
/// 1. Sender creates offer with file list
/// 2. Sender sends offer to receiver via DM
/// 3. Receiver accepts/rejects
/// 4. If accepted, receiver downloads files from sender's API
/// 5. Progress updates sent back to sender
class TransferOffer {
  final String offerId;
  final String senderCallsign;
  final String? senderNpub;
  String? receiverCallsign;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<TransferOfferFile> files;
  final int totalBytes;
  TransferOfferStatus status;

  // Progress tracking
  int bytesTransferred;
  int filesCompleted;
  String? currentFile;
  String? error;
  String? destinationPath; // Where receiver is saving files

  // Token for file serving (sender only)
  String? serveToken;

  TransferOffer({
    required this.offerId,
    required this.senderCallsign,
    this.senderNpub,
    this.receiverCallsign,
    required this.createdAt,
    required this.expiresAt,
    required this.files,
    required this.totalBytes,
    this.status = TransferOfferStatus.pending,
    this.bytesTransferred = 0,
    this.filesCompleted = 0,
    this.currentFile,
    this.error,
    this.destinationPath,
    this.serveToken,
  });

  /// Total number of files
  int get totalFiles => files.length;

  /// Check if offer has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Progress percentage (0-100)
  double get progressPercent =>
      totalBytes > 0 ? (bytesTransferred / totalBytes * 100) : 0;

  /// Time remaining until expiry
  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());

  /// Whether the offer is still actionable
  bool get isActionable =>
      status == TransferOfferStatus.pending && !isExpired;

  /// Whether the offer is active (transferring)
  bool get isActive =>
      status == TransferOfferStatus.accepted ||
      status == TransferOfferStatus.transferring;

  /// Generate a unique offer ID
  static String generateOfferId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode.abs() % 10000;
    return 'tr_${timestamp.toRadixString(36)}$random';
  }

  /// Create the manifest JSON for this offer
  Map<String, dynamic> toManifest() => {
    'offerId': offerId,
    'totalFiles': totalFiles,
    'totalBytes': totalBytes,
    'files': files.map((f) => f.toJson()).toList(),
  };

  /// Create the offer message to send to receiver
  Map<String, dynamic> toOfferMessage() => {
    'type': 'transfer_offer',
    'offerId': offerId,
    'senderCallsign': senderCallsign,
    if (senderNpub != null) 'senderNpub': senderNpub,
    'timestamp': createdAt.millisecondsSinceEpoch ~/ 1000,
    'expiresAt': expiresAt.millisecondsSinceEpoch ~/ 1000,
    'manifest': toManifest(),
  };

  /// Create a response message
  static Map<String, dynamic> createResponse({
    required String offerId,
    required bool accepted,
    required String receiverCallsign,
  }) => {
    'type': 'transfer_response',
    'offerId': offerId,
    'accepted': accepted,
    'receiverCallsign': receiverCallsign,
  };

  /// Create a progress message
  static Map<String, dynamic> createProgressMessage({
    required String offerId,
    required int bytesReceived,
    required int totalBytes,
    required int filesCompleted,
    String? currentFile,
  }) => {
    'type': 'transfer_progress',
    'offerId': offerId,
    'bytesReceived': bytesReceived,
    'totalBytes': totalBytes,
    'filesCompleted': filesCompleted,
    if (currentFile != null) 'currentFile': currentFile,
  };

  /// Create a completion message
  static Map<String, dynamic> createCompleteMessage({
    required String offerId,
    required bool success,
    required int bytesReceived,
    required int filesReceived,
    String? error,
  }) => {
    'type': 'transfer_complete',
    'offerId': offerId,
    'success': success,
    'bytesReceived': bytesReceived,
    'filesReceived': filesReceived,
    if (error != null) 'error': error,
  };

  Map<String, dynamic> toJson() => {
    'offerId': offerId,
    'senderCallsign': senderCallsign,
    if (senderNpub != null) 'senderNpub': senderNpub,
    if (receiverCallsign != null) 'receiverCallsign': receiverCallsign,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'files': files.map((f) => f.toJson()).toList(),
    'totalBytes': totalBytes,
    'status': status.name,
    'bytesTransferred': bytesTransferred,
    'filesCompleted': filesCompleted,
    if (currentFile != null) 'currentFile': currentFile,
    if (error != null) 'error': error,
    if (destinationPath != null) 'destinationPath': destinationPath,
  };

  factory TransferOffer.fromJson(Map<String, dynamic> json) {
    return TransferOffer(
      offerId: json['offerId'] as String,
      senderCallsign: json['senderCallsign'] as String,
      senderNpub: json['senderNpub'] as String?,
      receiverCallsign: json['receiverCallsign'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      files: (json['files'] as List)
          .map((f) => TransferOfferFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      totalBytes: json['totalBytes'] as int,
      status: TransferOfferStatus.values.byName(json['status'] as String),
      bytesTransferred: json['bytesTransferred'] as int? ?? 0,
      filesCompleted: json['filesCompleted'] as int? ?? 0,
      currentFile: json['currentFile'] as String?,
      error: json['error'] as String?,
      destinationPath: json['destinationPath'] as String?,
    );
  }

  /// Parse an incoming offer message
  factory TransferOffer.fromOfferMessage(Map<String, dynamic> json) {
    final manifest = json['manifest'] as Map<String, dynamic>;
    final files = (manifest['files'] as List)
        .map((f) => TransferOfferFile.fromJson(f as Map<String, dynamic>))
        .toList();

    return TransferOffer(
      offerId: json['offerId'] as String,
      senderCallsign: json['senderCallsign'] as String,
      senderNpub: json['senderNpub'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAt'] as int) * 1000,
      ),
      files: files,
      totalBytes: manifest['totalBytes'] as int,
      status: TransferOfferStatus.pending,
    );
  }

  TransferOffer copyWith({
    String? offerId,
    String? senderCallsign,
    String? senderNpub,
    String? receiverCallsign,
    DateTime? createdAt,
    DateTime? expiresAt,
    List<TransferOfferFile>? files,
    int? totalBytes,
    TransferOfferStatus? status,
    int? bytesTransferred,
    int? filesCompleted,
    String? currentFile,
    String? error,
    String? destinationPath,
    String? serveToken,
  }) {
    return TransferOffer(
      offerId: offerId ?? this.offerId,
      senderCallsign: senderCallsign ?? this.senderCallsign,
      senderNpub: senderNpub ?? this.senderNpub,
      receiverCallsign: receiverCallsign ?? this.receiverCallsign,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      files: files ?? this.files,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      filesCompleted: filesCompleted ?? this.filesCompleted,
      currentFile: currentFile ?? this.currentFile,
      error: error ?? this.error,
      destinationPath: destinationPath ?? this.destinationPath,
      serveToken: serveToken ?? this.serveToken,
    );
  }

  @override
  String toString() =>
      'TransferOffer(id: $offerId, from: $senderCallsign, '
      'files: $totalFiles, status: ${status.name})';
}
