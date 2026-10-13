import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/channel.dart';
import '../models/playback_status.dart';
import '../theme/app_theme.dart';
import '../services/stream_resolver.dart';

class VideoPanel extends StatefulWidget {
  final Channel? channel;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onVideoTap;
  final bool? controlsVisible;
  final ValueChanged<PlaybackStatus>? onPlaybackStatusChanged;

  const VideoPanel({
    super.key,
    required this.channel,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.onVideoTap,
    this.controlsVisible,
    this.onPlaybackStatusChanged,
  });

  @override
  State<VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<VideoPanel> {
  VideoPlayerController? _videoController;
  final StreamResolver _streamResolver = StreamResolver();
  VoidCallback? _videoListener;
  Timer? _renewalTimer;
  Timer? _recoveryTimer;
  Timer? _stabilityTimer;
  int _playbackGeneration = 0;
  int _recoveryAttempts = 0;
  bool _isResolvingStream = false;

  Timer? _overlayTimer;

  bool _isLoading = false;
  bool _hasError = false;
  bool _showOverlay = true;

  String _errorMessage = '';
  PlaybackStatus _reportedStatus = PlaybackStatus.idle;

  void _publishStatus(PlaybackStatus status) {
    if (_reportedStatus == status || !mounted) return;
    setState(() => _reportedStatus = status);
    final generation = _playbackGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _playbackGeneration &&
          _reportedStatus == status) {
        widget.onPlaybackStatusChanged?.call(status);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _publishControllerStatus(VideoPlayerController controller) {
    final value = controller.value;
    _publishStatus(value.hasError
        ? PlaybackStatus.error
        : !value.isInitialized || value.isBuffering
            ? PlaybackStatus.loading
            : value.isPlaying
                ? PlaybackStatus.playing
                : PlaybackStatus.paused);
  }

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldChannel = oldWidget.channel;
    final newChannel = widget.channel;
    final channelChanged =
        oldChannel?.id != newChannel?.id ||
        oldChannel?.streamUrl != newChannel?.streamUrl ||
        oldChannel?.webUrl != newChannel?.webUrl ||
        oldChannel?.playerType != newChannel?.playerType ||
        !mapEquals(oldChannel?.httpHeaders, newChannel?.httpHeaders);

    if (channelChanged) {
      _setupPlayer();
    }

    if (oldWidget.isFullScreen != widget.isFullScreen) {
      _showTemporaryOverlay();
    }
  }

  Future<void> _setupPlayer() async {
    final channel = widget.channel;
    final generation = ++_playbackGeneration;
    _recoveryAttempts = 0;
    _isResolvingStream = false;
    _cancelPlaybackTimers();

    _stopOverlayTimer();
    setState(() {
      _isLoading = channel != null;
      _hasError = false;
      _showOverlay = true;
      _errorMessage = '';
    });

    _publishStatus(channel == null ? PlaybackStatus.idle : PlaybackStatus.loading);
    await _disposeVideoController();
    if (!mounted || generation != _playbackGeneration) return;

    if (channel == null) {
      setState(() {
        _isLoading = false;
      });
      _publishStatus(PlaybackStatus.idle);
      return;
    }

    if (!channel.isHls) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Esta versión admite únicamente señales HLS directas.';
      });
      _publishStatus(PlaybackStatus.error);
      return;
    }

    await _setupHls(channel, generation);
  }

  bool _isCurrentPlayback(Channel channel, int generation) =>
      mounted &&
      generation == _playbackGeneration &&
      widget.channel?.id == channel.id;

  Future<void> _setupHls(
    Channel channel,
    int generation, {
    bool renewal = false,
  }) async {
    if (!_isCurrentPlayback(channel, generation) || _isResolvingStream) return;
    _isResolvingStream = true;
    VideoPlayerController? candidate;
    try {
      final stream = await _streamResolver.resolve(channel);
      if (!_isCurrentPlayback(channel, generation)) return;
      final controller =
          candidate = VideoPlayerController.networkUrl(
            stream.uri,
            httpHeaders: stream.headers,
          );

      // Keep a working picture while a signed URL is renewed in the background.
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!_isCurrentPlayback(channel, generation)) return;
      await controller.setLooping(true);
      if (!_isCurrentPlayback(channel, generation)) return;

      final previous = _videoController;
      final previousListener = _videoListener;
      if (previous != null) {
        try {
          await previous.pause();
        } catch (_) {}
      }
      if (!_isCurrentPlayback(channel, generation)) return;
      _videoController = controller;
      _videoListener = () {
        if (!_isCurrentPlayback(channel, generation) ||
            _videoController != controller) {
          return;
        }
        _publishControllerStatus(controller);
        if (!controller.value.hasError) return;
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage =
              'La señal se interrumpió. Reintentá o elegí otro canal.';
        });
        _scheduleRecovery(channel, generation);
      };
      controller.addListener(_videoListener!);
      if (previous != null) {
        unawaited(_releaseController(previous, previousListener));
      }

      await controller.play();

      if (!_isCurrentPlayback(channel, generation)) return;
      if (controller.value.hasError) {
        throw StateError('El reproductor rechazó la señal.');
      }

      setState(() {
        _isLoading = false;
        _hasError = false;
        _errorMessage = '';
      });

      _publishControllerStatus(controller);
      if (!renewal) _showTemporaryOverlay();
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      _stabilityTimer?.cancel();
      _stabilityTimer = Timer(const Duration(seconds: 30), () {
        if (_isCurrentPlayback(channel, generation) &&
            _videoController == controller &&
            !controller.value.hasError) {
          _recoveryAttempts = 0;
        }
      });
      _renewalTimer?.cancel();
      if (_streamResolver.needsRenewal(channel)) {
        _renewalTimer = Timer(const Duration(minutes: 5), () {
          if (_isCurrentPlayback(channel, generation)) {
            _setupHls(channel, generation, renewal: true);
          }
        });
      }
    } catch (error) {
      if (!_isCurrentPlayback(channel, generation)) return;

      final previousStillWorks =
          renewal &&
          _videoController != null &&
          _videoController!.value.isInitialized &&
          !_videoController!.value.hasError;
      if (!previousStillWorks) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _showOverlay = true;
          _errorMessage =
              error is StreamResolutionException
                  ? error.message
                  : 'Canal no disponible. Probá actualizar o elegir otro canal.';
        });
      }
      if (!previousStillWorks) _publishStatus(PlaybackStatus.error);
      if (previousStillWorks) {
        _renewalTimer?.cancel();
        _renewalTimer = Timer(const Duration(minutes: 5), () {
          if (_isCurrentPlayback(channel, generation)) {
            _recoveryAttempts = 0;
            _setupHls(channel, generation, renewal: true);
          }
        });
      } else if (error is! StreamResolutionException || error.retryable) {
        _scheduleRecovery(channel, generation);
      }
    } finally {
      if (candidate != null && candidate != _videoController) {
        unawaited(_releaseController(candidate, null));
      }
      if (_isCurrentPlayback(channel, generation)) _isResolvingStream = false;
    }
  }

  void _scheduleRecovery(Channel channel, int generation) {
    if (!_streamResolver.needsRenewal(channel) ||
        _recoveryTimer != null ||
        _recoveryAttempts >= 2 ||
        !_isCurrentPlayback(channel, generation)) {
      return;
    }
    _recoveryAttempts++;
    _recoveryTimer = Timer(const Duration(seconds: 3), () {
      _recoveryTimer = null;
      if (_isCurrentPlayback(channel, generation)) {
        _setupHls(channel, generation, renewal: _videoController != null);
      }
    });
  }

  void _cancelPlaybackTimers() {
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
  }

  Future<void> _releaseController(
    VideoPlayerController controller,
    VoidCallback? listener,
  ) async {
    if (listener != null) controller.removeListener(listener);
    try {
      await controller.dispose();
    } catch (_) {}
  }

  void _stopOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }

  void _showTemporaryOverlay() {
    _stopOverlayTimer();
    if (widget.controlsVisible != null) return;

    if (!mounted) return;

    setState(() {
      _showOverlay = true;
    });

    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;

      setState(() {
        _showOverlay = false;
      });
    });
  }

  Future<void> _disposeVideoController() async {
    final controller = _videoController;
    final listener = _videoListener;
    _videoController = null;
    _videoListener = null;

    if (controller != null) {
      try {
        await controller.pause();
      } catch (_) {}
      await _releaseController(controller, listener);
    }
  }

  @override
  void dispose() {
    _playbackGeneration++;
    _cancelPlaybackTimers();
    _streamResolver.dispose();
    _stopOverlayTimer();
    _disposeVideoController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final showControls = widget.controlsVisible ?? _showOverlay;
    return GestureDetector(
      key: const ValueKey('video-touch-surface'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onVideoTap ?? _showTemporaryOverlay,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(channel)),
            if (_isLoading) Positioned.fill(child: _buildLoadingOverlay()),
            if (_hasError) Positioned.fill(child: _buildErrorOverlay(channel)),
            if (channel != null && showControls && !_isLoading && !_hasError)
              _buildChannelBadge(channel),
            if (showControls && !widget.isFullScreen) _buildFullScreenButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Channel? channel) {
    if (channel == null) {
      return const Center(child: Text('Elegí un canal',
          style: TextStyle(color: AppColors.secondary, fontSize: 18)));
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(height: 12),
            Text('Cargando…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _buildErrorOverlay(Channel? channel) => ColoredBox(
        color: AppColors.background,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tv_off_rounded, color: AppColors.secondary, size: 28),
              const SizedBox(height: 8),
              Text(channel?.name ?? 'Canal', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_errorMessage, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.secondary, fontSize: 14)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _setupPlayer,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              ),
            ]),
          ),
        ),
      );

  Widget _buildChannelBadge(Channel channel) => Positioned(
        left: 12,
        right: 12,
        top: 12,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text(channel.id.toString().padLeft(2, '0'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(_reportedStatus.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _buildFullScreenButton() => Positioned(
        right: 8,
        bottom: 8,
        child: Material(
          color: AppColors.background.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          child: IconButton(
            key: const ValueKey('enter-fullscreen'),
            tooltip: 'Pantalla completa',
            onPressed: widget.onToggleFullScreen,
            icon: const Icon(Icons.fullscreen_rounded, size: 28),
          ),
        ),
      );
}
