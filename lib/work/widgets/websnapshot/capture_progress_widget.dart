/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../../services/i18n_service.dart';
import '../../services/web_snapshot_service.dart';

/// Widget showing capture progress
class CaptureProgressWidget extends StatelessWidget {
  final CaptureProgress progress;
  final VoidCallback? onCancel;

  const CaptureProgressWidget({
    super.key,
    required this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = I18nService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                if (progress.phase != CapturePhase.complete &&
                    progress.phase != CapturePhase.failed)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (progress.phase == CapturePhase.complete)
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 20,
                  )
                else
                  Icon(
                    Icons.error,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getPhaseLabel(progress.phase, i18n),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onCancel != null &&
                    progress.phase != CapturePhase.complete &&
                    progress.phase != CapturePhase.failed)
                  TextButton(
                    onPressed: onCancel,
                    child: Text(i18n.t('cancel')),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),

            const SizedBox(height: 8),

            // Message
            Text(
              progress.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            // Stats
            if (progress.totalPages > 0 || progress.totalAssets > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (progress.totalPages > 0) ...[
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${progress.pagesProcessed}/${progress.totalPages}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (progress.totalAssets > 0) ...[
                    Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${progress.assetsDownloaded}/${progress.totalAssets}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getPhaseLabel(CapturePhase phase, I18nService i18n) {
    switch (phase) {
      case CapturePhase.fetching:
        return i18n.t('work_websnapshot_phase_fetching');
      case CapturePhase.parsing:
        return i18n.t('work_websnapshot_phase_parsing');
      case CapturePhase.downloading:
        return i18n.t('work_websnapshot_phase_downloading');
      case CapturePhase.rewriting:
        return i18n.t('work_websnapshot_phase_rewriting');
      case CapturePhase.complete:
        return i18n.t('work_websnapshot_phase_complete');
      case CapturePhase.failed:
        return i18n.t('work_websnapshot_phase_failed');
    }
  }
}
