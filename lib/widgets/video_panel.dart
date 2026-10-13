import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/channel.dart';
import '../services/stream_resolver.dart';

class VideoPanel extends StatefulWidget {
  final Channel? channel;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  const VideoPanel({
    super.key,
    required this.channel,
    this.isFullScreen = false,
    this.onToggleFullScreen,
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
    await _disposeVideoController();

    if (!mounted || generation != _playbackGeneration) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _showOverlay = true;
      _errorMessage = '';
    });

    if (channel == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (!channel.isHls) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Esta versión admite únicamente señales HLS directas.';
      });
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
            _videoController != controller ||
            !controller.value.hasError) {
          return;
        }
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _showTemporaryOverlay,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(channel)),
            if (_isLoading) _buildLoadingOverlay(channel),
            if (_hasError) _buildErrorOverlay(channel),
            if (!_isLoading && !_hasError && channel != null && _showOverlay)
              _buildCleanChannelBadge(channel),
            if (!_isLoading && !_hasError && channel != null && _showOverlay)
              _buildFullScreenButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Channel? channel) {
    if (channel == null) {
      return const Center(
        child: Text(
          'Seleccioná un canal',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Center(
      child: FittedBox(
        fit: widget.isFullScreen ? BoxFit.contain : BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(Channel? channel) {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, 0.78),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Colors.redAccent,
              strokeWidth: 3,
            ),
            const SizedBox(height: 18),
            Text(
              channel == null ? 'Cargando...' : 'Cargando canal...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(Channel? channel) {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, 0.88),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(22, 24, 28, 0.96),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.10),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tv_off_rounded,
                color: Colors.redAccent,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text(
                channel?.name ?? 'Canal',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _setupPlayer,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCleanChannelBadge(Channel channel) {
    final channelNumber = channel.id.toString().padLeft(2, '0');

    return Positioned(
      left: 16,
      top: 16,
      child: AnimatedOpacity(
        opacity: _showOverlay ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, 0.76),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channelNumber,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                channel.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'EN VIVO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenButton() {
    return Positioned(
      right: 16,
      top: 16,
      child: Material(
        color: const Color.fromRGBO(0, 0, 0, 0.66),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _showTemporaryOverlay();
            widget.onToggleFullScreen?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(
              widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
