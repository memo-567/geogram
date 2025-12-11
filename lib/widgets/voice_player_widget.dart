import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/log_service.dart';
import '../services/audio_platform_stub.dart'
    if (dart.library.io) '../services/audio_platform_io.dart';

/// Voice message player widget with download indicator.
///
/// Simple player: Play button + elapsed/total counter
class VoicePlayerWidget extends StatefulWidget {
  /// Local file path or remote URL to the voice message
  final String filePath;

  /// Duration in seconds (from message metadata, for display before loading)
  final int? durationSeconds;

  /// Whether this is a local file (true) or needs to be downloaded (false)
  final bool isLocal;

  /// Callback when download is needed
  final Future<String?> Function()? onDownloadRequested;

  /// Background color (inherits from message bubble)
  final Color? backgroundColor;

  const VoicePlayerWidget({
    super.key,
    required this.filePath,
    this.durationSeconds,
    this.isLocal = true,
    this.onDownloadRequested,
    this.backgroundColor,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

enum _PlayerState { idle, downloading, loading, ready, playing }

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  final AudioService _audioService = AudioService();

  _PlayerState _state = _PlayerState.idle;
  Duration _duration = Duration.zero;
  int _elapsedSeconds = 0;
  String? _localFilePath;
  double _downloadProgress = 0.0;

  StreamSubscription<bool>? _playingSubscription;
  Timer? _downloadTimer;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  void _setupPlayer() {
    // Listen to playing state changes to know when playback ends
    _playingSubscription = _audioService.playingStream.listen((isPlaying) {
      if (!mounted) return;
      if (!isPlaying && _state == _PlayerState.playing) {
        _stopPlaybackTimer();
        setState(() {
          _state = _PlayerState.ready;
          _elapsedSeconds = 0;
        });
      }
    });

    // Initialize based on whether file is local or needs download
    if (widget.isLocal) {
      _loadLocalFile();
    } else {
      // Show known duration from metadata while in idle state
      if (widget.durationSeconds != null) {
        _duration = Duration(seconds: widget.durationSeconds!);
      }
      // Check if file is already cached locally
      _checkIfAlreadyCached();
    }
  }

  void _startPlaybackTimer() {
    _elapsedSeconds = 0;
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _state != _PlayerState.playing) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedSeconds++;
        // Auto-stop if we've reached the duration
        if (_elapsedSeconds >= _duration.inSeconds) {
          _elapsedSeconds = _duration.inSeconds;
        }
      });
    });
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  Future<void> _checkIfAlreadyCached() async {
    if (widget.onDownloadRequested == null) return;

    final path = await widget.onDownloadRequested!();
    if (path != null && mounted) {
      _localFilePath = path;
      setState(() {});
    }
  }

  Future<void> _loadLocalFile() async {
    final path = _localFilePath ?? widget.filePath;

    final file = PlatformFile(path);
    if (!await file.exists()) {
      LogService().log('VoicePlayerWidget: File not found: $path');
      return;
    }

    setState(() {
      _state = _PlayerState.loading;
    });

    try {
      await _audioService.initialize();
      await _audioService.load(path);
      if (!mounted) return;

      // Use metadata duration if available
      Duration actualDuration;
      if (widget.durationSeconds != null && widget.durationSeconds! > 0) {
        actualDuration = Duration(seconds: widget.durationSeconds!);
      } else {
        final fileDuration = await _audioService.getFileDuration(path);
        actualDuration = fileDuration ?? Duration.zero;
      }

      setState(() {
        _duration = actualDuration;
        _state = _PlayerState.ready;
      });
    } catch (e) {
      LogService().log('VoicePlayerWidget: Failed to load: $e');
      if (mounted) {
        setState(() {
          _state = _PlayerState.idle;
        });
      }
    }
  }

  Future<void> _download() async {
    if (widget.onDownloadRequested == null) return;

    setState(() {
      _state = _PlayerState.downloading;
      _downloadProgress = 0.0;
    });

    _downloadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _state != _PlayerState.downloading) {
        timer.cancel();
        return;
      }
      setState(() {
        _downloadProgress = (_downloadProgress + 0.05).clamp(0.0, 0.9);
      });
    });

    try {
      final localPath = await widget.onDownloadRequested!();
      _downloadTimer?.cancel();

      if (localPath != null && mounted) {
        setState(() {
          _localFilePath = localPath;
          _downloadProgress = 1.0;
        });
        await _loadLocalFile();
      } else if (mounted) {
        setState(() {
          _state = _PlayerState.idle;
        });
      }
    } catch (e) {
      _downloadTimer?.cancel();
      LogService().log('VoicePlayerWidget: Download failed: $e');
      if (mounted) {
        setState(() {
          _state = _PlayerState.idle;
        });
      }
    }
  }

  Future<void> _playFromCache() async {
    LogService().log('VoicePlayer: _playFromCache called, _state=$_state');
    if (_state != _PlayerState.idle) {
      LogService().log('VoicePlayer: _playFromCache: not idle, returning');
      return;
    }
    await _loadLocalFile();
    LogService().log('VoicePlayer: _playFromCache: after load, _state=$_state');
    if (_state == _PlayerState.ready) {
      LogService().log('VoicePlayer: _playFromCache: starting playback');
      setState(() {
        _state = _PlayerState.playing;
        _elapsedSeconds = 0;
      });
      _startPlaybackTimer();
      await _audioService.play();
      LogService().log('VoicePlayer: _playFromCache: play() returned, _state=$_state');
    }
  }

  Future<void> _togglePlayPause() async {
    LogService().log('VoicePlayer: _togglePlayPause called, _state=$_state');

    if (_state == _PlayerState.idle) {
      LogService().log('VoicePlayer: state is idle, checking local file');
      if (widget.isLocal || _localFilePath != null) {
        await _playFromCache();
      } else {
        _download();
      }
      return;
    }

    if (_state == _PlayerState.playing) {
      LogService().log('VoicePlayer: STOPPING playback');
      _stopPlaybackTimer();
      setState(() {
        _state = _PlayerState.ready;
        _elapsedSeconds = 0;
      });
      await _audioService.stop();
      LogService().log('VoicePlayer: stop() completed, state now=$_state');
    } else if (_state == _PlayerState.ready) {
      LogService().log('VoicePlayer: STARTING playback from ready');
      setState(() {
        _state = _PlayerState.playing;
        _elapsedSeconds = 0;
      });
      _startPlaybackTimer();
      await _audioService.play();
      LogService().log('VoicePlayer: play() completed');
    }
  }

  String _formatSeconds(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _downloadTimer?.cancel();
    _playbackTimer?.cancel();
    if (_state == _PlayerState.playing) {
      _audioService.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fgColor = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPlayButton(fgColor),
          const SizedBox(width: 8),
          _buildTimeDisplay(theme, fgColor),
          if (!widget.isLocal && _localFilePath != null) ...[
            const SizedBox(width: 4),
            _buildDownloadButton(fgColor),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayButton(Color fgColor) {
    switch (_state) {
      case _PlayerState.downloading:
      case _PlayerState.loading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: _state == _PlayerState.downloading ? _downloadProgress : null,
            color: fgColor,
          ),
        );

      case _PlayerState.playing:
        return IconButton(
          icon: Icon(Icons.stop, color: fgColor, size: 24),
          onPressed: () {
            LogService().log('VoicePlayer: STOP BUTTON PRESSED');
            _togglePlayPause();
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 16,
        );

      case _PlayerState.ready:
        return IconButton(
          icon: Icon(Icons.play_arrow, color: fgColor, size: 24),
          onPressed: _togglePlayPause,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 16,
        );

      case _PlayerState.idle:
        final hasLocalFile = widget.isLocal || _localFilePath != null;
        return IconButton(
          icon: Icon(Icons.play_arrow, color: fgColor, size: 24),
          onPressed: hasLocalFile ? _playFromCache : _togglePlayPause,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 16,
        );
    }
  }

  Widget _buildTimeDisplay(ThemeData theme, Color fgColor) {
    final totalSeconds = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (widget.durationSeconds ?? 0);

    // When playing: show "elapsed / total"
    // When not playing: show just "total"
    final String timeText;
    if (_state == _PlayerState.playing) {
      timeText = '${_formatSeconds(_elapsedSeconds)} / ${_formatSeconds(totalSeconds)}';
    } else {
      timeText = _formatSeconds(totalSeconds);
    }

    return Text(
      timeText,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: fgColor,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildDownloadButton(Color fgColor) {
    return IconButton(
      icon: Icon(Icons.download, color: fgColor.withOpacity(0.7), size: 20),
      onPressed: _saveToDevice,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 14,
      tooltip: 'Save to device',
    );
  }

  void _saveToDevice() {
    if (_localFilePath != null) {
      LogService().log('Voice file available at: $_localFilePath');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice message saved')),
      );
    }
  }
}
