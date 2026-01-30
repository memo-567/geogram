/*
 * Copyright (c) geogram
 * License: Apache-2.0
 *
 * Compose Dialog Widget - Compose new articles or replies
 */

import 'package:flutter/material.dart';
import 'package:nntp/nntp.dart';

import '../../services/nntp_service.dart';
import '../../services/profile_service.dart';
import '../utils/article_format.dart';

/// Dialog for composing new articles or replies
class ComposeDialog extends StatefulWidget {
  final String accountId;
  final String newsgroup;
  final NNTPArticle? replyTo;

  const ComposeDialog({
    super.key,
    required this.accountId,
    required this.newsgroup,
    this.replyTo,
  });

  @override
  State<ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<ComposeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _isPosting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.replyTo != null) {
      // Pre-fill reply
      final original = widget.replyTo!;

      // Set subject
      var subject = original.subject;
      if (!subject.toLowerCase().startsWith('re:')) {
        subject = 'Re: $subject';
      }
      _subjectController.text = subject;

      // Quote original
      _bodyController.text = ArticleFormat.quoteForReply(original);
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isPosting = true;
      _error = null;
    });

    try {
      final profile = ProfileService().getProfile();
      final from = profile?.callsign ?? 'Anonymous';
      // Construct email from callsign (Profile doesn't have email field)
      final callsign = profile?.callsign ?? 'anonymous';
      final email = '$callsign@nostr.net';

      final article = NNTPArticle(
        messageId: '', // Server will assign
        subject: _subjectController.text.trim(),
        from: '$from <$email>',
        date: DateTime.now(),
        references: widget.replyTo != null
            ? _buildReferences(widget.replyTo!)
            : null,
        newsgroups: widget.newsgroup,
        body: _bodyController.text.trim(),
      );

      // Validate
      final errors = ArticleFormat.validate(article);
      if (errors.isNotEmpty) {
        setState(() {
          _error = errors.join('\n');
          _isPosting = false;
        });
        return;
      }

      await NNTPService().post(widget.accountId, article);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isPosting = false;
        });
      }
    }
  }

  String _buildReferences(NNTPArticle original) {
    final refs = StringBuffer();
    if (original.references != null && original.references!.isNotEmpty) {
      refs.write(original.references);
      refs.write(' ');
    }
    refs.write(original.messageId);
    return refs.toString();
  }

  Future<void> _saveDraft() async {
    final profile = ProfileService().getProfile();
    final from = profile?.callsign ?? 'Anonymous';
    // Construct email from callsign (Profile doesn't have email field)
    final callsign = profile?.callsign ?? 'anonymous';
    final email = '$callsign@nostr.net';

    final article = NNTPArticle(
      messageId: '',
      subject: _subjectController.text.trim(),
      from: '$from <$email>',
      date: DateTime.now(),
      references: widget.replyTo != null
          ? _buildReferences(widget.replyTo!)
          : null,
      newsgroups: widget.newsgroup,
      body: _bodyController.text.trim(),
    );

    await NNTPService().saveDraft(article);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved')),
      );
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReply = widget.replyTo != null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isReply ? Icons.reply : Icons.edit,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReply ? 'Reply' : 'New Post',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.newsgroup,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Error
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Subject
                    TextFormField(
                      controller: _subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Subject is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Body
                    TextFormField(
                      controller: _bodyController,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 15,
                      minLines: 10,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Message is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isPosting ? null : _saveDraft,
                    child: const Text('Save Draft'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isPosting ? null : _post,
                    icon: _isPosting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isPosting ? 'Posting...' : 'Post'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
