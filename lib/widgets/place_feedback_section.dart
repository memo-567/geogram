/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../models/place.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../services/place_feedback_service.dart';
import '../services/profile_service.dart';
import '../util/feedback_comment_utils.dart';
import '../util/feedback_folder_utils.dart';

class PlaceLikeButton extends StatefulWidget {
  final Place place;
  final bool compact;

  const PlaceLikeButton({
    super.key,
    required this.place,
    this.compact = false,
  });

  @override
  State<PlaceLikeButton> createState() => _PlaceLikeButtonState();
}

class _PlaceLikeButtonState extends State<PlaceLikeButton> {
  final PlaceFeedbackService _feedbackService = PlaceFeedbackService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();

  bool _isSubmitting = false;
  int _likeCount = 0;
  bool _hasLiked = false;
  String? _currentNpub;

  String? get _contentPath => widget.place.folderPath;

  String get _placeId {
    final folderPath = widget.place.folderPath;
    if (folderPath != null && folderPath.isNotEmpty) {
      return path.basename(folderPath);
    }
    return widget.place.placeFolderName;
  }

  @override
  void initState() {
    super.initState();
    _currentNpub = _profileService.getProfile().npub;
    _loadLikes();
  }

  @override
  void didUpdateWidget(covariant PlaceLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.folderPath != widget.place.folderPath ||
        oldWidget.place.placeFolderName != widget.place.placeFolderName) {
      _currentNpub = _profileService.getProfile().npub;
      _loadLikes();
    }
  }

  Future<void> _loadLikes() async {
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) {
      return;
    }

    try {
      final npubs = await FeedbackFolderUtils.readFeedbackFile(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
      );

      final npub = _currentNpub;
      final hasLiked = npub != null && npub.isNotEmpty
          ? npubs.contains(npub)
          : false;

      if (!mounted) return;
      setState(() {
        _likeCount = npubs.length;
        _hasLiked = hasLiked;
      });
    } catch (e) {
      LogService().log('PlaceLikeButton: Error loading likes: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (_isSubmitting) return;

    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) return;

    final profile = _profileService.getProfile();
    if (profile.callsign.isEmpty) {
      _showMessage(_i18n.t('no_active_callsign'));
      return;
    }
    if (profile.npub.isEmpty) {
      _showMessage(_i18n.t('nostr_keys_required'));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final event = await _feedbackService.buildLikeEvent(_placeId);
      if (event == null) {
        _showMessage(_i18n.t('nostr_keys_required'));
        return;
      }

      final stationResult = await _feedbackService.toggleLikeOnStation(_placeId, event);
      if (!stationResult.success) {
        _showMessage(
          stationResult.error ?? _i18n.t('connection_failed'),
          isError: true,
        );
        return;
      }

      bool? isActive = stationResult.isActive;
      if (isActive == true) {
        await FeedbackFolderUtils.addFeedbackEvent(
          contentPath,
          FeedbackFolderUtils.feedbackTypeLikes,
          event,
        );
      } else if (isActive == false) {
        await FeedbackFolderUtils.removeFeedbackEvent(
          contentPath,
          FeedbackFolderUtils.feedbackTypeLikes,
          event.npub,
        );
      } else {
        isActive = await FeedbackFolderUtils.toggleFeedbackEvent(
          contentPath,
          FeedbackFolderUtils.feedbackTypeLikes,
          event,
        );
      }

      if (isActive == null) {
        _showMessage(_i18n.t('connection_failed'), isError: true);
        return;
      }

      final count = stationResult.count ?? await FeedbackFolderUtils.getFeedbackCount(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
      );

      if (!mounted) return;
      setState(() {
        _hasLiked = isActive!;
        _likeCount = count;
      });

      _showMessage(isActive ? _i18n.t('like_added') : _i18n.t('like_removed'));
    } catch (e) {
      _showMessage('Failed to update like: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) {
      return const SizedBox.shrink();
    }

    final labelStyle = TextStyle(
      fontWeight: _hasLiked ? FontWeight.bold : FontWeight.normal,
      color: _hasLiked ? Colors.amber.shade800 : theme.colorScheme.onSurface,
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _hasLiked
            ? Colors.amber.withValues(alpha: 0.2)
            : theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _likeCount.toString(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: _hasLiked ? Colors.amber.shade800 : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return OutlinedButton.icon(
      onPressed: _isSubmitting ? null : _toggleLike,
      icon: Icon(
        _hasLiked ? Icons.star : Icons.star_border,
        color: _hasLiked ? Colors.amber : theme.colorScheme.onSurfaceVariant,
        size: widget.compact ? 18 : 20,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_i18n.t('like'), style: labelStyle),
          const SizedBox(width: 6),
          badge,
        ],
      ),
      style: OutlinedButton.styleFrom(
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: widget.compact ? VisualDensity.compact : VisualDensity.standard,
        side: BorderSide(
          color: _hasLiked ? Colors.amber : theme.colorScheme.outline,
          width: _hasLiked ? 2 : 1,
        ),
        backgroundColor: _hasLiked ? Colors.amber.withValues(alpha: 0.1) : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class PlaceLikeCountBadge extends StatefulWidget {
  final Place place;
  final bool showZero;

  const PlaceLikeCountBadge({
    super.key,
    required this.place,
    this.showZero = true,
  });

  @override
  State<PlaceLikeCountBadge> createState() => _PlaceLikeCountBadgeState();
}

class _PlaceLikeCountBadgeState extends State<PlaceLikeCountBadge> {
  int? _count;

  String? get _contentPath => widget.place.folderPath;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void didUpdateWidget(covariant PlaceLikeCountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.folderPath != widget.place.folderPath ||
        oldWidget.place.placeFolderName != widget.place.placeFolderName) {
      _loadCount();
    }
  }

  Future<void> _loadCount() async {
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) {
      setState(() => _count = 0);
      return;
    }

    try {
      final count = await FeedbackFolderUtils.getFeedbackCount(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
      );
      if (!mounted) return;
      setState(() => _count = count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _count = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _count ?? 0;
    if (!widget.showZero && count == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star,
          size: 16,
          color: Colors.amber.shade700,
        ),
        const SizedBox(width: 4),
        Text(
          count.toString(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class PlaceFeedbackSection extends StatefulWidget {
  final Place place;

  const PlaceFeedbackSection({
    super.key,
    required this.place,
  });

  @override
  State<PlaceFeedbackSection> createState() => _PlaceFeedbackSectionState();
}

class _PlaceFeedbackSectionState extends State<PlaceFeedbackSection> {
  final PlaceFeedbackService _feedbackService = PlaceFeedbackService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();
  final TextEditingController _commentController = TextEditingController();

  bool _isLoading = false;
  bool _isSubmitting = false;
  List<FeedbackComment> _comments = [];

  String? get _contentPath => widget.place.folderPath;
  String get _placeId {
    final folderPath = widget.place.folderPath;
    if (folderPath != null && folderPath.isNotEmpty) {
      return path.basename(folderPath);
    }
    return widget.place.placeFolderName;
  }

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void didUpdateWidget(covariant PlaceFeedbackSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.folderPath != widget.place.folderPath ||
        oldWidget.place.placeFolderName != widget.place.placeFolderName) {
      _loadComments();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final comments = await FeedbackCommentUtils.loadComments(contentPath);

      comments.sort((a, b) => _parseCommentDate(b.created).compareTo(_parseCommentDate(a.created)));

      if (!mounted) return;
      setState(() {
        _comments = comments;
      });
    } catch (e) {
      LogService().log('PlaceFeedbackSection: Error loading feedback: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  DateTime _parseCommentDate(String created) {
    final normalized = created.replaceAll('_', ':');
    return DateTime.tryParse(normalized) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _addComment() async {
    if (_isSubmitting) return;
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) return;

    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final profile = _profileService.getProfile();
    if (profile.callsign.isEmpty) {
      _showMessage(_i18n.t('no_active_callsign'));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final signature = await _feedbackService.signComment(_placeId, content);
      await FeedbackCommentUtils.writeComment(
        contentPath: contentPath,
        author: profile.callsign,
        content: content,
        npub: profile.npub.isNotEmpty ? profile.npub : null,
        signature: signature,
      );

      _commentController.clear();
      await _loadComments();
      _showMessage(_i18n.t('comment_added'));

      _feedbackService.commentOnStation(
        _placeId,
        profile.callsign,
        content,
        npub: profile.npub.isNotEmpty ? profile.npub : null,
        signature: signature,
      ).ignore();
    } catch (e) {
      _showMessage('Failed to add comment: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentPath = _contentPath;
    if (contentPath == null || contentPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        Text(
          _comments.isEmpty
              ? _i18n.t('comments')
              : '${_i18n.t('comments')} (${_comments.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                decoration: InputDecoration(
                  hintText: _i18n.t('comment_hint'),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isSubmitting ? null : _addComment,
              icon: const Icon(Icons.send),
              tooltip: _i18n.t('add_comment'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _i18n.t('no_comments_yet'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ..._comments.map((comment) => _buildCommentCard(comment, theme)),
      ],
    );
  }

  Widget _buildCommentCard(FeedbackComment comment, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    comment.author,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  comment.created.replaceAll('_', ':'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment.content,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
