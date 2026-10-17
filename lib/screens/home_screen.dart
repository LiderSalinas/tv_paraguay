import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../models/playback_status.dart';
import '../services/channel_service.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_list.dart';
import '../widgets/video_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _channelService = ChannelService();
  final _tvFocusNode = FocusNode(debugLabel: 'tv_remote');
  final _listScroll = ScrollController();
  final _panelScroll = ScrollController();
  final _playback = ValueNotifier(PlaybackStatus.idle);

  List<Channel> _channels = [];
  Channel? _selectedChannel;
  int _focusedIndex = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _requestInFlight = false;
  bool _hasLoadedChannels = false;
  bool _isUsingRemoteChannels = false;
  bool _isFullScreen = false;
  bool _panelOpen = false;
  bool _controlsVisible = false;
  bool _remoteMode = false;
  bool _scrolling = false;
  Future<void> _systemUiTask = Future<void>.value();
  int _systemUiGeneration = 0;
  int _pointersDown = 0;
  bool _largeListText = false;
  String _errorMessage = '';
  String _typedNumber = '';
  Timer? _controlsTimer;
  Timer? _numberTimer;

  int get _selectedIndex => _channels.indexWhere((c) => c.id == _selectedChannel?.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChannels(showFeedback: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _numberTimer?.cancel();
    _tvFocusNode.dispose();
    _listScroll.dispose();
    _panelScroll.dispose();
    _playback.dispose();
    _systemUiGeneration++;
    unawaited(_systemUiTask.whenComplete(_restoreSystemUi));
    super.dispose();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_requestInFlight) {
      _loadChannels(showFeedback: false);
    }
    if (state != AppLifecycleState.resumed) _controlsTimer?.cancel();
    if (state == AppLifecycleState.resumed) _restartControlsTimer();
  }

  Future<void> _loadChannels({bool showFeedback = true}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    final previousId = _selectedChannel?.id;
    setState(() {
      _isLoading = !_hasLoadedChannels;
      _isRefreshing = _hasLoadedChannels;
      _errorMessage = '';
    });
    try {
      final result = await _channelService.getChannels();
      if (!mounted) return;
      final oldIndex = result.channels.indexWhere((c) => c.id == previousId);
      setState(() {
        _channels = result.channels;
        _selectedChannel = _channels.isEmpty
            ? null
            : _channels[oldIndex >= 0 ? oldIndex : 0];
        _focusedIndex = math.max(0, _selectedIndex);
        _isLoading = false;
        _isRefreshing = false;
        _hasLoadedChannels = true;
        _isUsingRemoteChannels = result.isRemote;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.isRemote
              ? 'Canales actualizados'
              : 'Usando la lista de respaldo'),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = 'No se pudo cargar la lista de canales.';
      });
    } finally {
      _requestInFlight = false;
    }
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    if ((!_controlsVisible && !_panelOpen) || _scrolling || _pointersDown > 0) return;
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
        _panelOpen = false;
      });
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _restartControlsTimer();
  }

  void _openPanel() {
    if (_channels.isEmpty) {
      _showControls();
      return;
    }
    setState(() {
      _panelOpen = true;
      _controlsVisible = true;
      _focusedIndex = math.max(0, _selectedIndex);
    });
    _scrollToFocus();
    _restartControlsTimer();
  }

  void _closePanel({bool hideControls = false}) {
    setState(() {
      _panelOpen = false;
      _scrolling = false;
      _controlsVisible = !hideControls;
    });
    _restartControlsTimer();
  }

  void _onVideoTap() {
    if (_isFullScreen) {
      if (_panelOpen) {
        _closePanel();
      } else {
        _openPanel();
      }
    } else {
      _showControls();
    }
  }

  void _selectChannel(Channel channel) {
    _numberTimer?.cancel();
    if (_selectedChannel?.id != channel.id) _playback.value = PlaybackStatus.loading;
    setState(() {
      _selectedChannel = channel;
      _focusedIndex = math.max(0, _selectedIndex);
      _typedNumber = '';
      _panelOpen = false;
      _scrolling = false;
      _controlsVisible = true;
    });
    _tvFocusNode.requestFocus();
    _scrollToFocus();
    _restartControlsTimer();
  }

  void _stepChannel(int delta) {
    if (_channels.isEmpty) return;
    final index = (math.max(0, _selectedIndex) + delta) % _channels.length;
    _selectChannel(_channels[index]);
  }

  void _moveFocus(int delta) {
    if (_channels.isEmpty) return;
    if (_isFullScreen && !_panelOpen) _openPanel();
    setState(() {
      _focusedIndex = (_focusedIndex + delta).clamp(0, _channels.length - 1);
    });
    _scrollToFocus();
    _restartControlsTimer();
  }

  void _scrollToFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _panelOpen ? _panelScroll : _listScroll;
      if (!controller.hasClients) return;
      final extent = ChannelList.rowExtent(context, largeText: _largeListText);
      final top = _focusedIndex * extent;
      final bottom = top + extent;
      final position = controller.position;
      var target = position.pixels;
      if (top < target) target = top;
      if (bottom > target + position.viewportDimension) {
        target = bottom - position.viewportDimension;
      }
      controller.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleFullScreen() {
    final enter = !_isFullScreen;
    final generation = ++_systemUiGeneration;
    setState(() {
      _isFullScreen = enter;
      _panelOpen = false;
      _scrolling = false;
      _typedNumber = '';
      _controlsVisible = enter;
    });
    _numberTimer?.cancel();
    _tvFocusNode.requestFocus();
    _restartControlsTimer();
    _scrollToFocus();

    // Update the interface immediately; serialize Android changes and discard
    // stale requests so a quick Back/exit during rotation is never ignored.
    _systemUiTask = _systemUiTask.then((_) async {
      if (!mounted || generation != _systemUiGeneration) return;
      await SystemChrome.setEnabledSystemUIMode(
        enter ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      if (!mounted || generation != _systemUiGeneration) return;
      await SystemChrome.setPreferredOrientations(enter
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }).catchError((Object error) {
      debugPrint('No se pudo ajustar la orientación: $error');
    });
    return _systemUiTask;
  }

  bool _handleBack() {
    if (_typedNumber.isNotEmpty) {
      _numberTimer?.cancel();
      setState(() => _typedNumber = '');
      return true;
    }
    if (_panelOpen) {
      _closePanel(hideControls: true);
      return true;
    }
    if (_controlsVisible) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
      return true;
    }
    if (_isFullScreen) {
      _toggleFullScreen();
      return true;
    }
    return false;
  }

  void _confirmNumber() {
    final number = int.tryParse(_typedNumber);
    _numberTimer?.cancel();
    final index = _channels.indexWhere((c) => c.id == number);
    if (index >= 0) {
      _selectChannel(_channels[index]);
    } else {
      setState(() => _typedNumber = '');
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = int.tryParse(key.keyLabel);
    if (!_remoteMode) setState(() => _remoteMode = true);
    _restartControlsTimer();
    if (digit != null && key.keyLabel.length == 1) {
      _numberTimer?.cancel();
      setState(() {
        _typedNumber = _typedNumber.length >= 2
            ? '$digit'
            : '$_typedNumber$digit';
      });
      _numberTimer = Timer(const Duration(milliseconds: 900), _confirmNumber);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.channelUp || key == LogicalKeyboardKey.mediaTrackNext) {
      _stepChannel(1);
    } else if (key == LogicalKeyboardKey.channelDown || key == LogicalKeyboardKey.mediaTrackPrevious) {
      _stepChannel(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (_typedNumber.isNotEmpty) {
        _confirmNumber();
      } else if (_isFullScreen && !_panelOpen) {
        _openPanel();
      } else if (_channels.isNotEmpty) {
        _selectChannel(_channels[_focusedIndex]);
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!_isFullScreen) _toggleFullScreen();
    } else if (key == LogicalKeyboardKey.arrowLeft && _panelOpen) {
      _closePanel(hideControls: true);
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      return _handleBack() ? KeyEventResult.handled : KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_panelOpen) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _controlsTimer?.cancel();
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _restartControlsTimer();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        canPop: !_isFullScreen && !_panelOpen && !_controlsVisible && _typedNumber.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Focus(
          focusNode: _tvFocusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Listener(
            onPointerDown: (_) {
              _pointersDown++;
              _controlsTimer?.cancel();
              if (_remoteMode) setState(() => _remoteMode = false);
            },
            onPointerUp: (_) {
              _pointersDown = math.max(0, _pointersDown - 1);
              _restartControlsTimer();
            },
            onPointerCancel: (_) {
              _pointersDown = math.max(0, _pointersDown - 1);
              _restartControlsTimer();
            },
            child: Scaffold(
              body: SafeArea(child: LayoutBuilder(builder: _buildLayout)),
            ),
          ),
        ),
      );

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final wide = width >= 760 || (width >= 600 && width > height);
    _largeListText = width >= 1000;
    final scale = MediaQuery.textScalerOf(context).scale(26) / 26;
    final headerHeight = math.max(82.0, 26 * scale * 2 * 1.2 + 24);
    final sidebarWidth = width >= 1200 ? 340.0 : 300.0;
    final mobileVideoHeight = math.min((width - 32) * 9 / 16, height * 0.36);
    final videoRect = _isFullScreen
        ? Rect.fromLTWH(0, 0, width, height)
        : wide
            ? Rect.fromLTWH(sidebarWidth + 32, headerHeight + 8,
                math.max(0, width - sidebarWidth - 48),
                math.max(0, height - headerHeight - 24))
            : Rect.fromLTWH(16, headerHeight + 8, width - 32, mobileVideoHeight);

    // The player stays at the same keyed location in this Stack in every layout.
    return Stack(
      children: [
        Positioned.fromRect(
          key: const ValueKey('persistent-player-position'),
          rect: videoRect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_isFullScreen ? 0 : 16),
            child: VideoPanel(
              key: const ValueKey('persistent-player'),
              channel: _selectedChannel,
              isFullScreen: _isFullScreen,
              onToggleFullScreen: _toggleFullScreen,
              onVideoTap: _onVideoTap,
              controlsVisible: _controlsVisible && !_panelOpen,
              onPlaybackStatusChanged: (status) {
                if (mounted) _playback.value = status;
              },
            ),
          ),
        ),
        if (!_isFullScreen) ...[
          Positioned(left: 0, right: 0, top: 0, height: headerHeight, child: _buildHeader()),
          Positioned(
            left: 16,
            right: wide ? width - sidebarWidth - 16 : 16,
            top: wide ? headerHeight + 8 : headerHeight + mobileVideoHeight + 28,
            bottom: 8,
            child: _buildMainList(),
          ),
        ],
        if (_isFullScreen && _controlsVisible && !_panelOpen)
          Positioned(left: 12, right: 12, bottom: 12, child: _buildControls()),
        if (_isFullScreen && _panelOpen)
          Positioned(
            key: const ValueKey('fullscreen-channel-panel'),
            left: 12,
            top: 12,
            bottom: 12,
            width: math.min(width - 24, math.max(260, math.min(340, width * 0.38))),
            child: _buildChannelPanel(),
          ),
        if (_typedNumber.isNotEmpty)
          Positioned(
            right: 20,
            top: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_typedNumber, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() => Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Image.asset('assets/branding/tv_paraguay_logo.jpg',
                      width: 44, height: 44, excludeFromSemantics: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      const TextSpan(children: [
                        TextSpan(text: 'TV ', style: TextStyle(color: AppColors.blue)),
                        TextSpan(text: 'Paraguay'),
                      ]),
                      semanticsLabel: 'TV Paraguay',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isRefreshing)
                    const SizedBox(width: 48, height: 48, child: Center(
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  else
                    IconButton(
                      key: const ValueKey('refresh-channels'),
                      tooltip: 'Actualizar canales',
                      onPressed: () => _loadChannels(),
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.secondary),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 2, child: Row(children: [
            Expanded(flex: 3, child: Container(color: AppColors.blue)),
            Expanded(child: Container(color: AppColors.red)),
          ])),
        ],
      );

  Widget _buildMainList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty && _channels.isEmpty) {
      return SingleChildScrollView(child: Column(children: [
        Text(_errorMessage, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _loadChannels, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      ]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          child: Row(children: [
            const Expanded(child: Text('Canales', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            Tooltip(
              message: _isUsingRemoteChannels ? 'Lista actualizada' : 'Lista de respaldo',
              child: Text('${_channels.length}', style: const TextStyle(fontSize: 14, color: AppColors.secondary)),
            ),
          ]),
        ),
        Expanded(child: _buildList(_listScroll)),
      ],
    );
  }

  Widget _buildList(ScrollController controller) => ValueListenableBuilder<PlaybackStatus>(
        valueListenable: _playback,
        builder: (_, status, __) => NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ChannelList(
            channels: _channels,
            selectedChannel: _selectedChannel,
            focusedChannelId: _remoteMode && _channels.isNotEmpty ? _channels[_focusedIndex].id : null,
            playbackStatus: status,
            scrollController: controller,
            largeText: _largeListText,
            onChannelSelected: _selectChannel,
          ),
        ),
      );

  Widget _buildChannelPanel() => Material(
        color: AppColors.background.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: [
              Row(children: [
                const Expanded(child: Text('Canales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                IconButton(
                  key: const ValueKey('close-channel-panel'),
                  tooltip: 'Cerrar canales',
                  onPressed: () => _closePanel(hideControls: true),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(child: _buildList(_panelScroll)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _controlButton('previous-channel', 'Canal anterior', Icons.skip_previous_rounded, () => _stepChannel(-1)),
                _controlButton('next-channel', 'Canal siguiente', Icons.skip_next_rounded, () => _stepChannel(1)),
                _controlButton('exit-fullscreen', 'Salir de pantalla completa', Icons.fullscreen_exit_rounded, _toggleFullScreen),
              ]),
            ],
          ),
        ),
      );

  Widget _buildControls() => Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: AppColors.background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Wrap(spacing: 4, children: [
              _controlButton('open-channel-panel', 'Canales', Icons.list_rounded, _openPanel),
              _controlButton('previous-channel', 'Canal anterior', Icons.skip_previous_rounded, () => _stepChannel(-1)),
              _controlButton('next-channel', 'Canal siguiente', Icons.skip_next_rounded, () => _stepChannel(1)),
              _controlButton('exit-fullscreen', 'Salir de pantalla completa', Icons.fullscreen_exit_rounded, _toggleFullScreen),
            ]),
          ),
        ),
      );

  Widget _controlButton(String key, String label, IconData icon, VoidCallback action) => IconButton(
        key: ValueKey(key),
        tooltip: label,
        onPressed: action,
        icon: Icon(icon, size: 28),
      );
}
