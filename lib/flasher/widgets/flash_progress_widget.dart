/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/flash_progress.dart';

/// Widget for displaying flash operation progress
class FlashProgressWidget extends StatelessWidget {
  final FlashProgress progress;
  final bool showDetails;

  const FlashProgressWidget({
    super.key,
    required this.progress,
    this.showDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status indicator
            _buildStatusRow(theme),

            const SizedBox(height: 12),

            // Progress bar
            _buildProgressBar(theme),

            if (showDetails && progress.isInProgress) ...[
              const SizedBox(height: 12),
              _buildDetails(theme),
            ],

            // Error message
            if (progress.isError && progress.error != null) ...[
              const SizedBox(height: 12),
              _buildError(theme),
            ],

            // Success message
            if (progress.isCompleted) ...[
              const SizedBox(height: 12),
              _buildSuccess(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(ThemeData theme) {
    return Row(
      children: [
        _buildStatusIcon(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getStatusTitle(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                progress.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        if (progress.isInProgress)
          Text(
            '${progress.percentage}%',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;
    bool spinning = false;

    switch (progress.status) {
      case FlashStatus.idle:
        icon = Icons.pause_circle_outline;
        color = Colors.grey;
        break;
      case FlashStatus.connecting:
        icon = Icons.cable;
        color = Colors.blue;
        spinning = true;
        break;
      case FlashStatus.syncing:
        icon = Icons.sync;
        color = Colors.blue;
        spinning = true;
        break;
      case FlashStatus.erasing:
        icon = Icons.cleaning_services;
        color = Colors.orange;
        spinning = true;
        break;
      case FlashStatus.writing:
        icon = Icons.edit;
        color = Colors.blue;
        spinning = true;
        break;
      case FlashStatus.verifying:
        icon = Icons.verified;
        color = Colors.purple;
        spinning = true;
        break;
      case FlashStatus.resetting:
        icon = Icons.restart_alt;
        color = Colors.teal;
        spinning = true;
        break;
      case FlashStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case FlashStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    final iconWidget = Icon(icon, color: color, size: 32);

    if (spinning) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Icon(icon, color: color, size: 18),
          ],
        ),
      );
    }

    return iconWidget;
  }

  String _getStatusTitle() {
    switch (progress.status) {
      case FlashStatus.idle:
        return 'Ready';
      case FlashStatus.connecting:
        return 'Connecting';
      case FlashStatus.syncing:
        return 'Syncing';
      case FlashStatus.erasing:
        return 'Erasing';
      case FlashStatus.writing:
        return 'Writing';
      case FlashStatus.verifying:
        return 'Verifying';
      case FlashStatus.resetting:
        return 'Resetting';
      case FlashStatus.completed:
        return 'Complete';
      case FlashStatus.error:
        return 'Error';
    }
  }

  Widget _buildProgressBar(ThemeData theme) {
    Color color;
    if (progress.isError) {
      color = Colors.red;
    } else if (progress.isCompleted) {
      color = Colors.green;
    } else {
      color = theme.colorScheme.primary;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.progress,
        backgroundColor: color.withOpacity(0.2),
        valueColor: AlwaysStoppedAnimation(color),
        minHeight: 8,
      ),
    );
  }

  Widget _buildDetails(ThemeData theme) {
    final details = <Widget>[];

    if (progress.totalBytes > 0) {
      details.add(
        _buildDetailItem(
          theme,
          Icons.storage,
          'Progress',
          progress.formattedProgress,
        ),
      );
    }

    if (progress.totalChunks > 0) {
      details.add(
        _buildDetailItem(
          theme,
          Icons.view_module,
          'Sectors',
          '${progress.currentChunk} / ${progress.totalChunks}',
        ),
      );
    }

    if (progress.elapsed != null) {
      details.add(
        _buildDetailItem(
          theme,
          Icons.timer,
          'Elapsed',
          progress.formattedElapsed,
        ),
      );
    }

    if (details.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: details,
    );
  }

  Widget _buildDetailItem(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.textTheme.bodySmall?.color),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              progress.error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flash completed successfully!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (progress.elapsed != null)
                  Text(
                    'Total time: ${progress.formattedElapsed}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact progress indicator for app bars or status lines
class CompactFlashProgress extends StatelessWidget {
  final FlashProgress progress;

  const CompactFlashProgress({
    super.key,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    if (!progress.isInProgress) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: progress.progress,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${progress.percentage}%',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
