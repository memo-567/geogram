/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'package:flutter/material.dart';
import '../bot/models/music_generation_state.dart';
import '../bot/models/music_track.dart';
import '../services/log_service.dart';
import 'music_player_widget.dart';

/// Widget to display music generation progress in chat bubbles.
/// Shows progress bar, phase, ETA, and optionally an FM player while generating.
class MusicProgressWidget extends StatefulWidget {
  /// Stream of generation state updates
  final Stream<MusicGenerationState> stateStream;

  /// Callback when cancel is requested
  final VoidCallback? onCancel;

  /// Callback when generation completes with a track
  final void Function(MusicTrack track)? onComplete;

  /// Background color (inherits from message bubble)
  final Color? backgroundColor;

  const MusicProgressWidget({
    super.key,
    required this.stateStream,
    this.onCancel,
    this.onComplete,
    this.backgroundColor,
  });

  @override
  State<MusicProgressWidget> createState() => _MusicProgressWidgetState();
}

class _MusicProgressWidgetState extends State<MusicProgressWidget> {
  MusicGenerationState? _state;
  StreamSubscription<MusicGenerationState>? _subscription;
  bool _completionNotified = false;

  @override
  void initState() {
    super.initState();
    print('>>> MusicProgressWidget: initState called, subscribing to stream');
    LogService().log('MusicProgressWidget: Subscribing to stream');
    _subscription = widget.stateStream.listen(
      (state) {
        print('>>> MusicProgressWidget: Received state: ${state.phase}');
        LogService().log('MusicProgressWidget: Received state: ${state.phase}');
        if (mounted) {
          setState(() {
            _state = state;
          });

          // Notify when generation completes with a track (only once)
          if (state.isSuccess && state.result != null && !_completionNotified) {
            _completionNotified = true;
            widget.onComplete?.call(state.result!);
          }
        }
      },
      onError: (error, stackTrace) {
        print('>>> MusicProgressWidget: Stream error: $error');
        LogService().log('MusicProgressWidget: Stream error: $error');
        LogService().log('MusicProgressWidget: Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _state = MusicGenerationState.failed(error.toString());
          });
        }
      },
      onDone: () {
        print('>>> MusicProgressWidget: Stream completed');
        LogService().log('MusicProgressWidget: Stream completed');
      },
    );
  }

  @override
  void dispose() {
    LogService().log('MusicProgressWidget: dispose called');
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return _buildLoadingState(context);
    }

    // If completed, show the music player
    if (state.isSuccess && state.result != null) {
      return MusicPlayerWidget(track: state.result!);
    }

    // If failed, show error
    if (state.isFailed) {
      return _buildErrorState(context, state);
    }

    // If FM is playing while AI generates
    if (state.isFMPlaying && state.fmTrack != null) {
      return _buildFMPlayingState(context, state);
    }

    // Show progress
    return _buildProgressState(context, state);
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Preparing music generation...',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressState(BuildContext context, MusicGenerationState state) {
    final theme = Theme.of(context);
    final bgColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fgColor = theme.colorScheme.onSurface;
    final accentColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase and message
          Row(
            children: [
              Icon(
                _getPhaseIcon(state.phase),
                size: 20,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.message ?? state.phaseDisplayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 6,
              backgroundColor: fgColor.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 8),

          // Progress and ETA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.progressString,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fgColor.withOpacity(0.7),
                ),
              ),
              if (state.etaString != null)
                Text(
                  state.etaString!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fgColor.withOpacity(0.7),
                  ),
                ),
            ],
          ),

          // Cancel button
          if (widget.onCancel != null && state.isInProgress) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: fgColor.withOpacity(0.7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFMPlayingState(
      BuildContext context, MusicGenerationState state) {
    final theme = Theme.of(context);
    final bgColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final accentColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FM Player
          MusicPlayerWidget(
            track: state.fmTrack!,
            showModel: false,
            backgroundColor: Colors.transparent,
          ),

          const SizedBox(height: 12),

          // AI generation progress
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: state.progress > 0 ? state.progress : null,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Generating higher quality version...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accentColor,
                    ),
                  ),
                ),
                if (state.etaString != null)
                  Text(
                    state.etaString!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: accentColor.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, MusicGenerationState state) {
    final theme = Theme.of(context);
    final bgColor =
        widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final errorColor = theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: errorColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.error ?? 'Music generation failed',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: errorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPhaseIcon(MusicPhase phase) {
    switch (phase) {
      case MusicPhase.queued:
        return Icons.hourglass_empty;
      case MusicPhase.downloading:
        return Icons.download;
      case MusicPhase.fmPlaying:
        return Icons.music_note;
      case MusicPhase.generating:
        return Icons.auto_awesome;
      case MusicPhase.postProcessing:
        return Icons.tune;
      case MusicPhase.saving:
        return Icons.save;
      case MusicPhase.completed:
        return Icons.check_circle;
      case MusicPhase.failed:
        return Icons.error;
      case MusicPhase.cancelled:
        return Icons.cancel;
    }
  }
}
