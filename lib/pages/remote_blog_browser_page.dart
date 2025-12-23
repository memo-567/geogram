/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:convert';
import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/blog_post.dart' as models;
import '../models/blog_comment.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import '../services/station_service.dart';
import '../services/storage_config.dart';
import '../widgets/blog_post_detail_widget.dart';

/// Page for browsing blog posts from a remote device
class RemoteBlogBrowserPage extends StatefulWidget {
  final RemoteDevice device;

  const RemoteBlogBrowserPage({
    super.key,
    required this.device,
  });

  @override
  State<RemoteBlogBrowserPage> createState() => _RemoteBlogBrowserPageState();
}

class _RemoteBlogBrowserPageState extends State<RemoteBlogBrowserPage> {
  final DevicesService _devicesService = DevicesService();
  final I18nService _i18n = I18nService();

  List<BlogPost> _posts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to load from cache first for instant response
      final cachedPosts = await _loadFromCache();
      if (cachedPosts.isNotEmpty) {
        setState(() {
          _posts = cachedPosts;
          _isLoading = false;
        });

        // Silently refresh from API in background
        _refreshFromApi();
        return;
      }

      // No cache - fetch from API
      await _fetchFromApi();
    } catch (e) {
      LogService().log('RemoteBlogBrowserPage: Error loading posts: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Load posts from cached data on disk
  Future<List<BlogPost>> _loadFromCache() async {
    try {
      final dataDir = StorageConfig().baseDir;
      final blogPath = '$dataDir/devices/${widget.device.callsign}/blog';
      final blogDir = Directory(blogPath);

      if (!await blogDir.exists()) {
        return [];
      }

      final posts = <BlogPost>[];
      await for (final entity in blogDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final data = json.decode(content) as Map<String, dynamic>;
            posts.add(BlogPost.fromJson(data));
          } catch (e) {
            LogService().log('Error reading blog post ${entity.path}: $e');
          }
        }
      }

      // Sort by timestamp descending
      posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      LogService().log('RemoteBlogBrowserPage: Loaded ${posts.length} cached posts');
      return posts;
    } catch (e) {
      LogService().log('RemoteBlogBrowserPage: Error loading cache: $e');
      return [];
    }
  }

  /// Fetch fresh posts from API
  Future<void> _fetchFromApi() async {
    try {
      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'GET',
        path: '/api/blog',
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> postsData = data is Map ? (data['posts'] ?? data) : data;

        setState(() {
          _posts = postsData.map((json) => BlogPost.fromJson(json)).toList();
          _isLoading = false;
        });
        LogService().log('RemoteBlogBrowserPage: Fetched ${_posts.length} posts from API');
      } else {
        throw Exception('HTTP ${response?.statusCode ?? "null"}: ${response?.body ?? "no response"}');
      }
    } catch (e) {
      throw e;
    }
  }

  /// Silently refresh from API in background
  void _refreshFromApi() {
    _fetchFromApi().catchError((e) {
      LogService().log('RemoteBlogBrowserPage: Background refresh failed: $e');
      // Don't update UI with error, keep showing cached data
    });
  }

  Future<void> _openPost(BlogPost post) async {
    // Try to load full post content from cache first
    models.BlogPost? fullPost = await _loadFullPostFromCache(post.id);

    // If not in cache, try to fetch from API
    if (fullPost == null) {
      fullPost = await _loadFullPostFromApi(post.id);
    }

    if (fullPost == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load blog post')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Capture non-null value for navigation
    final loadedPost = fullPost;

    // Navigate to detail page
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _RemoteBlogPostDetailPage(
          post: loadedPost,
          device: widget.device,
        ),
      ),
    );
  }

  /// Load full post content from cached markdown file
  Future<models.BlogPost?> _loadFullPostFromCache(String postId) async {
    try {
      final dataDir = StorageConfig().baseDir;
      final devicePath = '$dataDir/devices/${widget.device.callsign}';
      final blogPath = '$devicePath/blog';

      // Check if blog directory exists
      final blogDir = Directory(blogPath);
      if (!await blogDir.exists()) return null;

      // Blog posts are stored in blog/YYYY/postId/post.md
      await for (final yearEntity in blogDir.list()) {
        if (yearEntity is Directory) {
          final postDir = Directory('${yearEntity.path}/$postId');
          final postFile = File('${postDir.path}/post.md');

          if (await postFile.exists()) {
            final content = await postFile.readAsString();
            return models.BlogPost.fromText(content, postId);
          }
        }
      }

      return null;
    } catch (e) {
      LogService().log('RemoteBlogBrowserPage: Error loading post from cache: $e');
      return null;
    }
  }

  /// Load full post content from API
  Future<models.BlogPost?> _loadFullPostFromApi(String postId) async {
    try {
      // Fetch the post details via JSON API
      final response = await _devicesService.makeDeviceApiRequest(
        callsign: widget.device.callsign,
        method: 'GET',
        path: '/api/blog/$postId',
      );

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] != true) {
          LogService().log('RemoteBlogBrowserPage: API returned error: ${data['error']}');
          return null;
        }

        // Convert JSON to BlogPost model
        final commentsList = <BlogComment>[];
        if (data['comments'] != null) {
          for (final c in data['comments'] as List) {
            final commentData = c as Map<String, dynamic>;
            final commentMetadata = <String, String>{};
            if (commentData['npub'] != null) commentMetadata['npub'] = commentData['npub'] as String;
            if (commentData['signature'] != null) commentMetadata['signature'] = commentData['signature'] as String;

            commentsList.add(BlogComment(
              id: commentData['id'] as String?,
              author: commentData['author'] as String? ?? 'Unknown',
              timestamp: commentData['timestamp'] as String? ?? '',
              content: commentData['content'] as String? ?? '',
              metadata: commentMetadata,
            ));
          }
        }

        // Build metadata map
        final postMetadata = <String, String>{};
        if (data['npub'] != null) postMetadata['npub'] = data['npub'] as String;
        if (data['signature'] != null) postMetadata['signature'] = data['signature'] as String;

        return models.BlogPost(
          id: data['id'] as String? ?? postId,
          author: data['author'] as String? ?? 'Unknown',
          timestamp: data['timestamp'] as String? ?? '',
          edited: data['edited'] as String?,
          title: data['title'] as String? ?? 'Untitled',
          description: data['description'] as String?,
          location: data['location'] as String?,
          status: models.BlogStatus.fromString(data['status'] as String? ?? 'draft'),
          tags: (data['tags'] as List?)?.map((t) => t.toString()).toList() ?? [],
          content: data['content'] as String? ?? '',
          comments: commentsList,
          metadata: postMetadata,
        );
      }

      return null;
    } catch (e) {
      LogService().log('RemoteBlogBrowserPage: Error loading post from API: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.displayName} - Blog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPosts,
            tooltip: _i18n.t('refresh'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _i18n.t('error_loading_data'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPosts,
                        child: Text(_i18n.t('retry')),
                      ),
                    ],
                  ),
                )
              : _posts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No blog posts',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This device has no published blog posts',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _posts.length,
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        return _buildPostCard(theme, post);
                      },
                    ),
    );
  }

  Widget _buildPostCard(ThemeData theme, BlogPost post) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openPost(post),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                post.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Author and timestamp
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    post.author,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    post.timestamp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),

              // Tags
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: post.tags.map((tag) {
                    return Chip(
                      label: Text(
                        tag,
                        style: theme.textTheme.bodySmall,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],

              // Comments count
              if (post.commentCount > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.comment,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount} ${post.commentCount == 1 ? 'comment' : 'comments'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail page for viewing a remote blog post
class _RemoteBlogPostDetailPage extends StatelessWidget {
  final models.BlogPost post;
  final RemoteDevice device;

  const _RemoteBlogPostDetailPage({
    required this.post,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService();
    final theme = Theme.of(context);

    // Get station URL for shareable link
    String? stationUrl = device.url;
    if (stationUrl == null || stationUrl.isEmpty) {
      final preferredStation = StationService().getPreferredStation();
      stationUrl = preferredStation?.url;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('blog_post')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BlogPostDetailWidget(
            post: post,
            collectionPath: '', // Not used for remote posts
            canEdit: false, // Read-only for remote posts
            stationUrl: stationUrl,
            profileIdentifier: device.callsign,
          ),
          const SizedBox(height: 24),
          // Show comments section (read-only)
          if (post.comments.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 16),
            Text(
              '${i18n.t('comments')} (${post.comments.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...post.comments.map((comment) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            comment.author,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.schedule,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            comment.timestamp,
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
            }),
          ] else ...[
            const Divider(),
            const SizedBox(height: 16),
            Text(
              i18n.t('no_comments_yet'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Blog post data model
class BlogPost {
  final String id;
  final String title;
  final String author;
  final String timestamp;
  final String status;
  final List<String> tags;
  final int commentCount;

  BlogPost({
    required this.id,
    required this.title,
    required this.author,
    required this.timestamp,
    required this.status,
    required this.tags,
    required this.commentCount,
  });

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    return BlogPost(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      author: json['author'] as String? ?? 'Unknown',
      timestamp: json['timestamp'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      tags: (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [],
      commentCount: json['commentCount'] as int? ?? 0,
    );
  }
}
