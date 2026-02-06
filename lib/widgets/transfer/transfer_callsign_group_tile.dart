import 'package:flutter/material.dart';

import '../../transfer/models/callsign_transfer_group.dart';
import '../../transfer/models/transfer_models.dart';
import 'transfer_progress_widget.dart';

/// Expandable tile widget for a group of transfers to/from one callsign.
///
/// Collapsed state shows:
/// - Direction icon (download/upload)
/// - Callsign name
/// - File count + total size
/// - Progress bar with percentage and speed (if active)
/// - Status chip (e.g., "3 active", "1 queued", "Done", "2 failed")
///
/// Expanded state shows:
/// - All individual transfers using `TransferListItem`
class TransferCallsignGroupTile extends StatefulWidget {
  final CallsignTransferGroup group;
  final void Function(Transfer)? onTransferTap;
  final void Function(Transfer)? onPause;
  final void Function(Transfer)? onCancel;
  final void Function(Transfer)? onRetry;
  final void Function(Transfer)? onResume;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String, bool)? onTransferSelected;
  final bool initiallyExpanded;

  /// Callback when user taps to open a file (for completed transfers)
  final void Function(Transfer)? onOpenFile;

  /// Callback when user taps "Open folder" in the menu
  final void Function(Transfer)? onOpenFolder;

  /// Callback when user taps "Delete" in the menu
  final void Function(Transfer)? onDelete;

  /// Callback when user taps "Copy path" in the menu
  final void Function(Transfer)? onCopyPath;

  const TransferCallsignGroupTile({
    super.key,
    required this.group,
    this.onTransferTap,
    this.onPause,
    this.onCancel,
    this.onRetry,
    this.onResume,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onTransferSelected,
    this.initiallyExpanded = false,
    this.onOpenFile,
    this.onOpenFolder,
    this.onDelete,
    this.onCopyPath,
  });

  @override
  State<TransferCallsignGroupTile> createState() =>
      _TransferCallsignGroupTileState();
}

class _TransferCallsignGroupTileState extends State<TransferCallsignGroupTile>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed header (always visible)
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: direction icon, callsign, status chip
                  Row(
                    children: [
                      _buildDirectionIcon(theme),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.callsign,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${group.totalFiles} ${group.totalFiles == 1 ? 'file' : 'files'}  ${_formatBytes(group.totalBytes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusChip(theme),
                      const SizedBox(width: 8),
                      RotationTransition(
                        turns: _iconTurns,
                        child: Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  // Progress bar (if active transfers)
                  if (group.activeFiles > 0) ...[
                    const SizedBox(height: 12),
                    TransferProgressWidget(
                      bytesTransferred: group.bytesTransferred,
                      totalBytes: group.totalBytes,
                      speedBytesPerSecond: group.speedBytesPerSecond,
                      eta: group.estimatedTimeRemaining,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded content (individual transfers)
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildExpandedContent(theme),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionIcon(ThemeData theme) {
    final isDownload = widget.group.direction == TransferDirection.download;
    final icon = isDownload ? Icons.download : Icons.upload;
    final color = isDownload ? Colors.blue : Colors.green;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 24, color: color),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final group = widget.group;
    String label = group.statusLabel;
    Color color;
    IconData? icon;

    if (group.failedFiles > 0) {
      color = Colors.red;
      icon = Icons.error;
    } else if (group.activeFiles > 0) {
      color = Colors.blue;
      icon = Icons.sync;
    } else if (group.queuedFiles > 0) {
      color = Colors.orange;
      icon = Icons.schedule;
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    // Sort transfers: active first, then queued, then completed/failed
    final sorted = List<Transfer>.from(widget.group.transfers)
      ..sort((a, b) {
        int priority(Transfer t) {
          if (t.isActive) return 0;
          if (t.isPending) return 1;
          if (t.isFailed) return 2;
          return 3;
        }
        return priority(a).compareTo(priority(b));
      });

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          // List of individual transfers
          ...sorted.asMap().entries.map((entry) {
            final index = entry.key;
            final transfer = entry.value;
            final isLast = index == sorted.length - 1;
            final isSelected = widget.selectedIds.contains(transfer.id);
            return Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _buildCompactTransferItem(
                theme,
                transfer,
                isSelected,
                isLast,
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Builds a more compact version of the transfer item for the expanded list
  Widget _buildCompactTransferItem(
    ThemeData theme,
    Transfer transfer,
    bool isSelected,
    bool isLast,
  ) {
    // Determine if this transfer can be opened (completed downloads)
    final canOpenFile = transfer.isCompleted &&
        transfer.direction == TransferDirection.download &&
        widget.onOpenFile != null;

    // Show menu for completed/failed transfers
    final showMenu = (transfer.isCompleted || transfer.isFailed) &&
        (widget.onOpenFolder != null ||
            widget.onDelete != null ||
            widget.onCopyPath != null);

    return InkWell(
      onTap: () {
        if (widget.selectionMode) {
          widget.onTransferSelected?.call(transfer.id, !isSelected);
        } else if (canOpenFile) {
          // Open file for completed downloads
          widget.onOpenFile?.call(transfer);
        } else {
          // Show transfer details
          widget.onTransferTap?.call(transfer);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            // Selection checkbox
            if (widget.selectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (val) =>
                    widget.onTransferSelected?.call(transfer.id, val ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            // Tree connector
            Text(
              isLast ? '\u2514\u2500 ' : '\u251c\u2500 ',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            // File icon
            _buildFileIcon(theme, transfer),
            const SizedBox(width: 8),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.filename ?? 'Unknown file',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (transfer.isActive) ...[
                    const SizedBox(height: 4),
                    TransferProgressBar(
                      progress: transfer.progressPercent / 100,
                      height: 4,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status/progress
            _buildCompactStatus(theme, transfer),
            // Actions (for active transfers) or Menu (for completed/failed)
            if (!widget.selectionMode) ...[
              if (transfer.isActive || transfer.isPending)
                _buildCompactActions(transfer)
              else if (showMenu)
                _buildTransferMenu(transfer)
              else
                const SizedBox(width: 32),
            ],
          ],
        ),
      ),
    );
  }

  /// Build the three-dot menu for completed/failed transfers
  Widget _buildTransferMenu(Transfer transfer) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: 'More options',
      onSelected: (value) {
        switch (value) {
          case 'open_folder':
            widget.onOpenFolder?.call(transfer);
            break;
          case 'delete':
            widget.onDelete?.call(transfer);
            break;
          case 'copy_path':
            widget.onCopyPath?.call(transfer);
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onOpenFolder != null)
          const PopupMenuItem(
            value: 'open_folder',
            child: Row(
              children: [
                Icon(Icons.folder_open, size: 18),
                SizedBox(width: 8),
                Text('Open folder'),
              ],
            ),
          ),
        if (widget.onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 18),
                SizedBox(width: 8),
                Text('Delete'),
              ],
            ),
          ),
        if (widget.onCopyPath != null)
          const PopupMenuItem(
            value: 'copy_path',
            child: Row(
              children: [
                Icon(Icons.copy, size: 18),
                SizedBox(width: 8),
                Text('Copy path'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFileIcon(ThemeData theme, Transfer transfer) {
    final mimeType = transfer.mimeType ?? '';
    IconData icon;
    Color color;

    if (mimeType.startsWith('image/')) {
      icon = Icons.image;
      color = Colors.pink;
    } else if (mimeType.startsWith('video/')) {
      icon = Icons.video_file;
      color = Colors.red;
    } else if (mimeType.startsWith('audio/')) {
      icon = Icons.audio_file;
      color = Colors.orange;
    } else if (mimeType.startsWith('text/')) {
      icon = Icons.description;
      color = Colors.blue;
    } else if (mimeType.contains('pdf')) {
      icon = Icons.picture_as_pdf;
      color = Colors.red;
    } else if (mimeType.contains('zip') ||
        mimeType.contains('tar') ||
        mimeType.contains('rar')) {
      icon = Icons.folder_zip;
      color = Colors.amber;
    } else {
      icon = Icons.insert_drive_file;
      color = theme.colorScheme.primary;
    }

    return Icon(icon, size: 20, color: color);
  }

  Widget _buildCompactStatus(ThemeData theme, Transfer transfer) {
    if (transfer.isActive) {
      return Text(
        '${transfer.progressPercent.toStringAsFixed(0)}%',
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    String label;
    Color color;

    switch (transfer.status) {
      case TransferStatus.queued:
      case TransferStatus.waiting:
        label = 'Queued';
        color = Colors.grey;
        break;
      case TransferStatus.completed:
        label = 'Done';
        color = Colors.green;
        break;
      case TransferStatus.failed:
        label = 'Failed';
        color = Colors.red;
        break;
      case TransferStatus.cancelled:
        label = 'Cancelled';
        color = Colors.grey;
        break;
      case TransferStatus.paused:
        label = 'Paused';
        color = Colors.amber;
        break;
      default:
        label = transfer.status.name;
        color = theme.colorScheme.onSurfaceVariant;
    }

    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildCompactActions(Transfer transfer) {
    final actions = <Widget>[];

    if (transfer.canPause && widget.onPause != null) {
      actions.add(IconButton(
        icon: const Icon(Icons.pause, size: 18),
        onPressed: () => widget.onPause?.call(transfer),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Pause',
      ));
    }

    if (transfer.canResume && widget.onResume != null) {
      actions.add(IconButton(
        icon: const Icon(Icons.play_arrow, size: 18),
        onPressed: () => widget.onResume?.call(transfer),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Resume',
      ));
    }

    if (transfer.canRetry && widget.onRetry != null) {
      actions.add(IconButton(
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: () => widget.onRetry?.call(transfer),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Retry',
      ));
    }

    if (transfer.canCancel && widget.onCancel != null) {
      actions.add(IconButton(
        icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
        onPressed: () => widget.onCancel?.call(transfer),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Cancel',
      ));
    }

    if (actions.isEmpty) {
      return const SizedBox(width: 32);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
