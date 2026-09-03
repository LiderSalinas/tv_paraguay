import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/channel.dart';

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

    _stopOverlayTimer();
    await _disposeVideoController();

    if (!mounted) return;

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

    await _setupHls(channel);
  }

  Future<void> _setupHls(Channel channel) async {
    try {
      if (channel.streamUrl.trim().isEmpty) {
        throw Exception('Este canal no tiene streamUrl');
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(channel.streamUrl),
        httpHeaders: channel.httpHeaders,
      );

      _videoController = controller;

      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = false;
        _errorMessage = '';
      });

      _showTemporaryOverlay();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _showOverlay = true;
        _errorMessage = 'Canal no disponible. Probá actualizar o elegir otro canal.';
      });
    }
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

    if (controller != null) {
      try {
        await controller.pause();
        await controller.dispose();
      } catch (_) {}
    }

    _videoController = null;
  }

  @override
  void dispose() {
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
            Positioned.fill(
              child: _buildContent(channel),
            ),
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
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
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
