/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../models/voicememo_content.dart';

/// Rating widget for voice memo clips
///
/// Supports both star ratings (1-5) and like/dislike buttons,
/// configurable via [ratingType].
class VoiceMemoRatingWidget extends StatelessWidget {
  /// Current user's star rating (null if not rated)
  final int? currentStars;

  /// Current user's like/dislike (true = liked, false = disliked, null = none)
  final bool? currentLiked;

  /// Type of rating to display
  final RatingType ratingType;

  /// Called when user selects a star rating (1-5)
  final void Function(int stars)? onStarsChanged;

  /// Called when user likes or dislikes (true = like, false = dislike)
  final void Function(bool liked)? onLikeChanged;

  /// Whether the widget is interactive
  final bool enabled;

  const VoiceMemoRatingWidget({
    super.key,
    this.currentStars,
    this.currentLiked,
    required this.ratingType,
    this.onStarsChanged,
    this.onLikeChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stars rating
        if (ratingType == RatingType.stars || ratingType == RatingType.both) ...[
          _buildStarsRating(theme),
          if (ratingType == RatingType.both) const SizedBox(width: 16),
        ],

        // Like/Dislike buttons
        if (ratingType == RatingType.likeDislike || ratingType == RatingType.both)
          _buildLikeDislike(theme),
      ],
    );
  }

  Widget _buildStarsRating(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        final isSelected = currentStars != null && currentStars! >= starNumber;

        return GestureDetector(
          onTap: enabled && onStarsChanged != null
              ? () => onStarsChanged!(starNumber)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              isSelected ? Icons.star : Icons.star_border,
              size: 28,
              color: isSelected
                  ? Colors.amber
                  : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLikeDislike(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button
        IconButton(
          onPressed: enabled && onLikeChanged != null
              ? () => onLikeChanged!(true)
              : null,
          icon: Icon(
            currentLiked == true ? Icons.thumb_up : Icons.thumb_up_outlined,
            color: currentLiked == true
                ? Colors.green
                : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Like',
        ),

        // Dislike button
        IconButton(
          onPressed: enabled && onLikeChanged != null
              ? () => onLikeChanged!(false)
              : null,
          icon: Icon(
            currentLiked == false ? Icons.thumb_down : Icons.thumb_down_outlined,
            color: currentLiked == false
                ? Colors.red
                : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Dislike',
        ),
      ],
    );
  }
}

/// Compact rating display widget showing aggregated ratings
class VoiceMemoRatingDisplayWidget extends StatelessWidget {
  /// Social data containing rating aggregates
  final ClipSocialData social;

  /// Type of rating to display
  final RatingType ratingType;

  const VoiceMemoRatingDisplayWidget({
    super.key,
    required this.social,
    required this.ratingType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stars average
        if (ratingType == RatingType.stars || ratingType == RatingType.both) ...[
          const Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            social.starsCount > 0
                ? '${social.averageStars.toStringAsFixed(1)} (${social.starsCount})'
                : '-',
            style: theme.textTheme.bodySmall,
          ),
          if (ratingType == RatingType.both) const SizedBox(width: 12),
        ],

        // Like/Dislike counts
        if (ratingType == RatingType.likeDislike || ratingType == RatingType.both) ...[
          const Icon(Icons.thumb_up_outlined, size: 16, color: Colors.green),
          const SizedBox(width: 4),
          Text('${social.likes}', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          const Icon(Icons.thumb_down_outlined, size: 16, color: Colors.red),
          const SizedBox(width: 4),
          Text('${social.dislikes}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
