/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/video.dart';
import '../models/blog_comment.dart';
import '../services/video_service.dart';
import '../services/log_service.dart';
import '../services/profile_service.dart';
import '../services/station_service.dart';
import '../services/i18n_service.dart';
import '../widgets/video_tile_widget.dart';
import '../widgets/video_detail_widget.dart';
import '../widgets/blog_comment_widget.dart';
import '../dialogs/new_video_dialog.dart';

/// YouTube-style video browser with grid layout
class VideoBrowserPage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;

  const VideoBrowserPage({
    super.key,
    required this.collectionPath,
    required this.collectionTitle,
  });

  @override
  State<VideoBrowserPage> createState() => _VideoBrowserPageState();
}

class _VideoBrowserPageState extends State<VideoBrowserPage> {
  final VideoService _videoService = VideoService();
  final ProfileService _profileService = ProfileService();
  final StationService _stationService = StationService();
  final I18nService _i18n = I18nService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Video> _allVideos = [];
  List<Video> _filteredVideos = [];
  bool _isLoading = true;
  String? _stationUrl;
  String? _profileIdentifier;
  String? _currentUserNpub;
  VideoCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterVideos);
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final profile = _profileService.getProfile();
    _currentUserNpub = profile.npub;

    final connectedRelay = _stationService.getConnectedStation();
    _stationUrl = connectedRelay?.url;
    _profileIdentifier = profile.nickname.isNotEmpty
        ? profile.nickname
        : profile.callsign;

    await _videoService.initializeCollection(
      widget.collectionPath,
      callsign: profile.callsign,
      creatorNpub: _currentUserNpub,
    );

    await _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);

    final videos = await _videoService.loadVideos(
      category: _selectedCategory,
      userNpub: _currentUserNpub,
    );

    setState(() {
      _allVideos = videos;
      _filteredVideos = videos;
      _isLoading = false;
    });

    _filterVideos();
  }

  void _filterVideos() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredVideos = _allVideos;
      } else {
        _filteredVideos = _allVideos.where((video) {
          return video.getTitle().toLowerCase().contains(query) ||
                 video.tags.any((tag) => tag.toLowerCase().contains(query)) ||
                 video.getDescription().toLowerCase().contains(query) ||
                 video.category.displayName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _selectCategory(VideoCategory? category) {
    setState(() {
      _selectedCategory = category;
    });
    _loadVideos();
  }

  Future<void> _openVideoDetail(Video video) async {
    final fullVideo = await _videoService.loadFullVideoWithFeedback(
      video.id,
      userNpub: _currentUserNpub,
    );

    if (!mounted || fullVideo == null) return;

    final comments = await _videoService.loadComments(video.id);

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => _VideoWatchPage(
          video: fullVideo,
          comments: comments,
          collectionPath: widget.collectionPath,
          videoService: _videoService,
          profileService: _profileService,
          i18n: _i18n,
          currentUserNpub: _currentUserNpub,
          stationUrl: _stationUrl,
          profileIdentifier: _profileIdentifier,
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      await _loadVideos();
    }
  }

  Future<void> _uploadVideo() async {
    try {
      LogService().log('VideoBrowserPage: Upload video button pressed');

      final existingTags = await _videoService.getAllTags();

      if (!mounted) return;

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => NewVideoDialog(existingTags: existingTags),
          fullscreenDialog: true,
        ),
      );

      if (result != null && mounted) {
        // Show uploading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(_i18n.t('uploading_video')),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );

        final profile = _profileService.getProfile();
        final video = await _videoService.createVideo(
          title: result['title'] as String,
          description: result['description'] as String?,
          sourceVideoPath: result['videoFilePath'] as String,
          category: result['category'] as VideoCategory,
          visibility: result['visibility'] as VideoVisibility,
          tags: result['tags'] as List<String>?,
          npub: profile.npub,
          nsec: profile.nsec,
          latitude: result['latitude'] as double?,
          longitude: result['longitude'] as double?,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }

        if (video != null && mounted) {
          LogService().log('VideoBrowserPage: Video uploaded: ${video.getTitle()}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_i18n.t('video_created')),
              backgroundColor: Colors.green,
            ),
          );
          await _loadVideos();
        }
      }
    } catch (e, stack) {
      LogService().log('VideoBrowserPage: ERROR uploading video: $e');
      LogService().log('VideoBrowserPage: Stack trace: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_i18n.t('upload_failed')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App bar with search
          _buildAppBar(theme),
          // Category filter chips
          _buildCategoryChips(theme),
          // Video grid or empty state
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredVideos.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(theme))
          else
            _buildVideoGrid(theme),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadVideo,
        icon: const Icon(Icons.upload),
        label: Text(_i18n.t('upload')),
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 140,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.surface,
              ],
            ),
          ),
        ),
      ),
      title: Text(_i18n.t('videos')),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _i18n.t('search_videos'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _filterVideos();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(ThemeData theme) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // All categories chip
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(_i18n.t('all')),
                selected: _selectedCategory == null,
                onSelected: (_) => _selectCategory(null),
              ),
            ),
            // Individual category chips
            ...VideoCategory.values.take(10).map((category) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(category.displayName),
                  selected: _selectedCategory == category,
                  onSelected: (_) => _selectCategory(category),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final isSearching = _searchController.text.isNotEmpty;
    final hasFilter = _selectedCategory != null;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSearching || hasFilter
                    ? Icons.search_off
                    : Icons.video_library_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? _i18n.t('no_matching_videos')
                    : _i18n.t('no_videos_yet'),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? _i18n.t('try_different_search_term')
                    : _i18n.t('upload_first_video'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (!isSearching && !hasFilter) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _uploadVideo,
                  icon: const Icon(Icons.upload),
                  label: Text(_i18n.t('upload_video')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGrid(ThemeData theme) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          // Responsive grid: calculate columns based on width
          final width = constraints.crossAxisExtent;
          int crossAxisCount;
          if (width > 1400) {
            crossAxisCount = 5;
          } else if (width > 1100) {
            crossAxisCount = 4;
          } else if (width > 800) {
            crossAxisCount = 3;
          } else if (width > 500) {
            crossAxisCount = 2;
          } else {
            crossAxisCount = 1;
          }

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.9, // More compact card
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final video = _filteredVideos[index];
                return VideoTileWidget(
                  video: video,
                  onTap: () => _openVideoDetail(video),
                );
              },
              childCount: _filteredVideos.length,
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen video watch page (like YouTube video page)
class _VideoWatchPage extends StatefulWidget {
  final Video video;
  final List<BlogComment> comments;
  final String collectionPath;
  final VideoService videoService;
  final ProfileService profileService;
  final I18nService i18n;
  final String? currentUserNpub;
  final String? stationUrl;
  final String? profileIdentifier;

  const _VideoWatchPage({
    required this.video,
    required this.comments,
    required this.collectionPath,
    required this.videoService,
    required this.profileService,
    required this.i18n,
    required this.currentUserNpub,
    this.stationUrl,
    this.profileIdentifier,
  });

  @override
  State<_VideoWatchPage> createState() => _VideoWatchPageState();
}

class _VideoWatchPageState extends State<_VideoWatchPage> {
  late Video _video;
  late List<BlogComment> _comments;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _video = widget.video;
    _comments = widget.comments;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshVideo() async {
    final fullVideo = await widget.videoService.loadFullVideoWithFeedback(
      _video.id,
      userNpub: widget.currentUserNpub,
    );
    if (fullVideo != null && mounted) {
      final comments = await widget.videoService.loadComments(_video.id);
      setState(() {
        _video = fullVideo;
        _comments = comments;
      });
    }
  }

  Future<void> _handleFeedback(String type) async {
    final profile = widget.profileService.getProfile();
    if (profile.npub.isEmpty || profile.nsec.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('nostr_key_required'))),
      );
      return;
    }

    bool? result;
    switch (type) {
      case 'like':
        result = await widget.videoService.toggleLike(_video.id, profile.npub, profile.nsec);
        break;
      case 'dislike':
        result = await widget.videoService.toggleDislike(_video.id, profile.npub, profile.nsec);
        break;
    }

    if (result != null) {
      _hasChanges = true;
      await _refreshVideo();
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    final profile = widget.profileService.getProfile();
    if (profile.npub.isEmpty || profile.nsec.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('nostr_key_required'))),
      );
      return;
    }

    final commentId = await widget.videoService.addComment(
      videoId: _video.id,
      author: profile.callsign,
      content: _commentController.text.trim(),
      npub: profile.npub,
      nsec: profile.nsec,
    );

    if (commentId != null && mounted) {
      _commentController.clear();
      _hasChanges = true;
      await _refreshVideo();
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final success = await widget.videoService.deleteComment(
      videoId: _video.id,
      commentId: commentId,
      userNpub: widget.currentUserNpub,
    );

    if (success && mounted) {
      _hasChanges = true;
      await _refreshVideo();
    }
  }

  Future<void> _deleteVideo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('delete_video')),
        content: Text(widget.i18n.t('delete_video_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(widget.i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await widget.videoService.deleteVideo(_video.id);
      if (success && mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = widget.videoService.isAdmin(widget.currentUserNpub);
    final canEdit = isAdmin || _video.npub == widget.currentUserNpub;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _hasChanges) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video and description (main content)
                  Expanded(
                    flex: 3,
                    child: _buildMainContent(theme, canEdit),
                  ),
                  // Comments sidebar
                  SizedBox(
                    width: 400,
                    child: _buildCommentsSidebar(theme),
                  ),
                ],
              );
            } else {
              return _buildMainContent(theme, canEdit, showComments: true);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme, bool canEdit, {bool showComments = false}) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Back button
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          actions: [
            if (canEdit)
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white),
                ),
                onSelected: (value) {
                  if (value == 'delete') _deleteVideo();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Text(widget.i18n.t('delete')),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        // Video detail widget
        SliverToBoxAdapter(
          child: VideoDetailWidget(
            video: _video,
            collectionPath: widget.collectionPath,
            canEdit: canEdit,
            stationUrl: widget.stationUrl,
            profileIdentifier: widget.profileIdentifier,
            onLike: () => _handleFeedback('like'),
            onDislike: () => _handleFeedback('dislike'),
          ),
        ),
        // Comments section (for mobile view)
        if (showComments) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${widget.i18n.t('comments')} (${_comments.length})',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildCommentInput(theme)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final comment = _comments[index];
                final canDelete = widget.videoService.isAdmin(widget.currentUserNpub) ||
                    comment.npub == widget.currentUserNpub;
                return BlogCommentWidget(
                  comment: comment,
                  canDelete: canDelete,
                  onDelete: canDelete && comment.id != null
                      ? () => _deleteComment(comment.id!)
                      : null,
                );
              },
              childCount: _comments.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ],
    );
  }

  Widget _buildCommentsSidebar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${widget.i18n.t('comments')} (${_comments.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Comment input
          _buildCommentInput(theme),
          // Comments list
          Expanded(
            child: _comments.isEmpty
                ? Center(
                    child: Text(
                      widget.i18n.t('no_comments_yet'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final comment = _comments[index];
                      final canDelete = widget.videoService.isAdmin(widget.currentUserNpub) ||
                          comment.npub == widget.currentUserNpub;
                      return BlogCommentWidget(
                        comment: comment,
                        canDelete: canDelete,
                        onDelete: canDelete && comment.id != null
                            ? () => _deleteComment(comment.id!)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: widget.i18n.t('write_comment'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _addComment(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: _addComment,
          ),
        ],
      ),
    );
  }
}
