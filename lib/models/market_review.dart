/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Model representing a verified review for a marketplace item
class MarketReview {
  final String reviewer;
  final String reviewerNpub;
  final String itemId;
  final String orderId;
  final String created;
  final int rating; // 1-5 stars
  final bool verifiedPurchase;
  final String title;
  final String review;
  final String? pros;
  final String? cons;
  final int helpfulYes;
  final int helpfulNo;
  final Map<String, String> metadata; // npub, signature

  MarketReview({
    required this.reviewer,
    required this.reviewerNpub,
    required this.itemId,
    required this.orderId,
    required this.created,
    required this.rating,
    this.verifiedPurchase = true,
    required this.title,
    required this.review,
    this.pros,
    this.cons,
    this.helpfulYes = 0,
    this.helpfulNo = 0,
    this.metadata = const {},
  });

  /// Parse timestamp to DateTime
  DateTime get dateTime {
    try {
      final normalized = created.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Get NOSTR public key
  String? get npub => metadata['npub'];

  /// Get signature
  String? get signature => metadata['signature'];

  /// Check if review is signed with NOSTR
  bool get isSigned => metadata.containsKey('signature');

  /// Check if review is verified purchase
  bool get isVerified => verifiedPurchase;

  /// Calculate helpfulness ratio
  double get helpfulnessRatio {
    final total = helpfulYes + helpfulNo;
    if (total == 0) return 0.0;
    return helpfulYes / total;
  }

  /// Get star rating display (e.g., "★★★★★" for 5 stars)
  String get starDisplay {
    return '★' * rating + '☆' * (5 - rating);
  }

  /// Export review as text format for file storage
  String exportAsText() {
    final buffer = StringBuffer();

    // Required fields
    buffer.writeln('REVIEWER: $reviewer');
    buffer.writeln('REVIEWER_NPUB: $reviewerNpub');
    buffer.writeln('ITEM_ID: $itemId');
    buffer.writeln('ORDER_ID: $orderId');
    buffer.writeln('CREATED: $created');
    buffer.writeln('RATING: $rating');
    buffer.writeln('VERIFIED_PURCHASE: ${verifiedPurchase ? 'yes' : 'no'}');
    buffer.writeln();

    // Title and review
    buffer.writeln('TITLE: $title');
    buffer.writeln();
    buffer.writeln('REVIEW:');
    buffer.writeln(review);
    buffer.writeln();

    // Pros and cons
    if (pros != null && pros!.isNotEmpty) {
      buffer.writeln('PROS:');
      buffer.writeln(pros);
      buffer.writeln();
    }

    if (cons != null && cons!.isNotEmpty) {
      buffer.writeln('CONS:');
      buffer.writeln(cons);
      buffer.writeln();
    }

    // Helpfulness
    if (helpfulYes > 0 || helpfulNo > 0) {
      buffer.writeln('HELPFUL_YES: $helpfulYes');
      buffer.writeln('HELPFUL_NO: $helpfulNo');
      buffer.writeln();
    }

    // Additional metadata (excluding signature which must be last)
    final regularMetadata = Map<String, String>.from(metadata);
    final sig = regularMetadata.remove('signature');

    for (var entry in regularMetadata.entries) {
      buffer.writeln('--> ${entry.key}: ${entry.value}');
    }

    // Signature must be last if present
    if (sig != null) {
      buffer.writeln('--> signature: $sig');
    }

    return buffer.toString();
  }

  /// Parse review from file text
  static MarketReview fromText(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty review file');
    }

    String? reviewer;
    String? reviewerNpub;
    String? itemId;
    String? orderId;
    String? created;
    int? rating;
    bool verifiedPurchase = false;
    String? title;
    String? review;
    String? pros;
    String? cons;
    int helpfulYes = 0;
    int helpfulNo = 0;
    Map<String, String> metadata = {};

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('REVIEWER: ')) {
        reviewer = line.substring(10).trim();
      } else if (line.startsWith('REVIEWER_NPUB: ')) {
        reviewerNpub = line.substring(15).trim();
      } else if (line.startsWith('ITEM_ID: ')) {
        itemId = line.substring(9).trim();
      } else if (line.startsWith('ORDER_ID: ')) {
        orderId = line.substring(10).trim();
      } else if (line.startsWith('CREATED: ')) {
        created = line.substring(9).trim();
      } else if (line.startsWith('RATING: ')) {
        rating = int.tryParse(line.substring(8).trim());
      } else if (line.startsWith('VERIFIED_PURCHASE: ')) {
        verifiedPurchase = line.substring(19).trim().toLowerCase() == 'yes';
      } else if (line.startsWith('TITLE: ')) {
        title = line.substring(7).trim();
      } else if (line.startsWith('REVIEW:')) {
        // Parse multi-line review
        final reviewLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('PROS:') &&
               !lines[i].startsWith('CONS:') &&
               !lines[i].startsWith('HELPFUL_YES:') &&
               !lines[i].startsWith('HELPFUL_NO:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            reviewLines.add(lines[i]);
          }
          i++;
        }
        review = reviewLines.join('\n').trim();
        continue;
      } else if (line.startsWith('PROS:')) {
        // Parse multi-line pros
        final prosLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('CONS:') &&
               !lines[i].startsWith('HELPFUL_YES:') &&
               !lines[i].startsWith('HELPFUL_NO:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            prosLines.add(lines[i]);
          }
          i++;
        }
        pros = prosLines.join('\n').trim();
        continue;
      } else if (line.startsWith('CONS:')) {
        // Parse multi-line cons
        final consLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('HELPFUL_YES:') &&
               !lines[i].startsWith('HELPFUL_NO:') &&
               !lines[i].startsWith('-->')) {
          if (lines[i].trim().isNotEmpty) {
            consLines.add(lines[i]);
          }
          i++;
        }
        cons = consLines.join('\n').trim();
        continue;
      } else if (line.startsWith('HELPFUL_YES: ')) {
        helpfulYes = int.tryParse(line.substring(13).trim()) ?? 0;
      } else if (line.startsWith('HELPFUL_NO: ')) {
        helpfulNo = int.tryParse(line.substring(12).trim()) ?? 0;
      } else if (line.startsWith('-->')) {
        // Parse metadata
        final metaLine = line.substring(3).trim();
        final colonIndex = metaLine.indexOf(':');
        if (colonIndex > 0) {
          final key = metaLine.substring(0, colonIndex).trim();
          final value = metaLine.substring(colonIndex + 1).trim();
          metadata[key] = value;
        }
      }

      i++;
    }

    // Validate required fields
    if (reviewer == null || reviewerNpub == null || itemId == null ||
        orderId == null || created == null || rating == null ||
        title == null || review == null) {
      throw Exception('Missing required review fields');
    }

    return MarketReview(
      reviewer: reviewer,
      reviewerNpub: reviewerNpub,
      itemId: itemId,
      orderId: orderId,
      created: created,
      rating: rating,
      verifiedPurchase: verifiedPurchase,
      title: title,
      review: review,
      pros: pros,
      cons: cons,
      helpfulYes: helpfulYes,
      helpfulNo: helpfulNo,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  MarketReview copyWith({
    String? reviewer,
    String? reviewerNpub,
    String? itemId,
    String? orderId,
    String? created,
    int? rating,
    bool? verifiedPurchase,
    String? title,
    String? review,
    String? pros,
    String? cons,
    int? helpfulYes,
    int? helpfulNo,
    Map<String, String>? metadata,
  }) {
    return MarketReview(
      reviewer: reviewer ?? this.reviewer,
      reviewerNpub: reviewerNpub ?? this.reviewerNpub,
      itemId: itemId ?? this.itemId,
      orderId: orderId ?? this.orderId,
      created: created ?? this.created,
      rating: rating ?? this.rating,
      verifiedPurchase: verifiedPurchase ?? this.verifiedPurchase,
      title: title ?? this.title,
      review: review ?? this.review,
      pros: pros ?? this.pros,
      cons: cons ?? this.cons,
      helpfulYes: helpfulYes ?? this.helpfulYes,
      helpfulNo: helpfulNo ?? this.helpfulNo,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'MarketReview(reviewer: $reviewer, item: $itemId, rating: $rating)';
  }
}
