import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/channel.dart';
import '../services/channel_service.dart';
import '../widgets/channel_list.dart';
import '../widgets/video_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChannelService _channelService = ChannelService();
  final FocusNode _tvFocusNode = FocusNode(debugLabel: 'tv_box_focus');
  final ScrollController _scrollController = ScrollController();

  List<Channel> _channels = [];
  Channel? _selectedChannel;

  bool _isLoading = true;
  bool _isFullScreen = false;
  String _errorMessage = '';

  String _typedChannelNumber = '';
  bool _showChannelNumberOverlay = false;
  bool _channelNumberNotFound = false;
  Timer? _channelNumberTimer;

  int get _selectedIndex {
    if (_selectedChannel == null) return -1;

    return _channels.indexWhere(
      (channel) => channel.id == _selectedChannel!.id,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadChannels();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tvFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _channelNumberTimer?.cancel();
    _tvFocusNode.dispose();
    _scrollController.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    super.dispose();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final channels = await _channelService.getChannels();

      setState(() {
        _channels = channels;
        _selectedChannel = channels.isNotEmpty ? channels.first : null;
        _isLoading = false;
      });

      _requestTvFocus();
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudo cargar la lista de canales.';
      });

      _requestTvFocus();
    }
  }

  void _requestTvFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tvFocusNode.hasFocus) {
        _tvFocusNode.requestFocus();
      }
    });
  }

  void _selectChannel(Channel channel) {
    final index = _channels.indexWhere((item) => item.id == channel.id);

    setState(() {
      _selectedChannel = channel;
    });

    if (index >= 0) {
      _scrollToSelected(index);
    }

    _requestTvFocus();
  }

  void _selectChannelByIndex(int index) {
    if (_channels.isEmpty) return;

    final safeIndex = index.clamp(0, _channels.length - 1);
    final channel = _channels[safeIndex];

    setState(() {
      _selectedChannel = channel;
    });

    _scrollToSelected(safeIndex);
    _requestTvFocus();
  }

  void _nextChannel() {
    if (_channels.isEmpty) return;

    final currentIndex = _selectedIndex;
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + 1) % _channels.length;

    _selectChannelByIndex(nextIndex);
  }

  void _previousChannel() {
    if (_channels.isEmpty) return;

    final currentIndex = _selectedIndex;
    final previousIndex = currentIndex <= 0
        ? _channels.length - 1
        : currentIndex - 1;

    _selectChannelByIndex(previousIndex);
  }

  void _scrollToSelected(int index) {
    if (!_scrollController.hasClients) return;

    const itemHeight = 98.0;
    final targetOffset = (index * itemHeight) - 120;

    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      targetOffset.clamp(min, max),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleFullScreen() async {
    final nextValue = !_isFullScreen;

    setState(() {
      _isFullScreen = nextValue;
    });

    if (nextValue) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _requestTvFocus();
  }

  Future<void> _enterFullScreen() async {
    if (_isFullScreen) return;
    await _toggleFullScreen();
  }

  Future<void> _exitFullScreen() async {
    if (!_isFullScreen) return;
    await _toggleFullScreen();
  }

  void _handleDigitInput(String digit) {
    if (_channels.isEmpty) return;

    _channelNumberTimer?.cancel();

    String nextNumber = _typedChannelNumber + digit;

    if (nextNumber.length > 3) {
      nextNumber = digit;
    }

    if (nextNumber.startsWith('0') && nextNumber.length > 1) {
      nextNumber = nextNumber.replaceFirst(RegExp(r'^0+'), '');
      if (nextNumber.isEmpty) {
        nextNumber = '0';
      }
    }

    setState(() {
      _typedChannelNumber = nextNumber;
      _showChannelNumberOverlay = true;
      _channelNumberNotFound = false;
    });

    _channelNumberTimer = Timer(
      const Duration(milliseconds: 950),
      _confirmTypedChannelNumber,
    );
  }

  void _confirmTypedChannelNumber() {
    if (_typedChannelNumber.trim().isEmpty) {
      _hideChannelNumberOverlay();
      return;
    }

    final number = int.tryParse(_typedChannelNumber);

    if (number == null) {
      _hideChannelNumberOverlay();
      return;
    }

    final index = _channels.indexWhere((channel) => channel.id == number);

    if (index >= 0) {
      _selectChannelByIndex(index);

      _channelNumberTimer?.cancel();
      _channelNumberTimer = Timer(
        const Duration(milliseconds: 450),
        _hideChannelNumberOverlay,
      );
    } else {
      setState(() {
        _channelNumberNotFound = true;
      });

      _channelNumberTimer?.cancel();
      _channelNumberTimer = Timer(
        const Duration(milliseconds: 900),
        _hideChannelNumberOverlay,
      );
    }
  }

  void _hideChannelNumberOverlay() {
    if (!mounted) return;

    setState(() {
      _typedChannelNumber = '';
      _showChannelNumberOverlay = false;
      _channelNumberNotFound = false;
    });

    _requestTvFocus();
  }

  String? _digitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      return '0';
    }

    if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      return '1';
    }

    if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      return '2';
    }

    if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      return '3';
    }

    if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      return '4';
    }

    if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      return '5';
    }

    if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      return '6';
    }

    if (key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7) {
      return '7';
    }

    if (key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8) {
      return '8';
    }

    if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      return '9';
    }

    return null;
  }

  KeyEventResult _handleTvRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final digit = _digitFromKey(key);

    if (digit != null) {
      _handleDigitInput(digit);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      _nextChannel();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      _previousChannel();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (_typedChannelNumber.isNotEmpty) {
        _channelNumberTimer?.cancel();
        _confirmTypedChannelNumber();
      } else {
        _toggleFullScreen();
      }

      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _enterFullScreen();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _exitFullScreen();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_typedChannelNumber.isNotEmpty) {
        _hideChannelNumberOverlay();
        return KeyEventResult.handled;
      }

      if (_isFullScreen) {
        _exitFullScreen();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _tvFocusNode,
      autofocus: true,
      onKeyEvent: _handleTvRemoteKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _requestTvFocus,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: _isFullScreen
              ? null
              : AppBar(
                  title: const Text('TV Paraguay'),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  actions: [
                    IconButton(
                      tooltip: 'Actualizar canales',
                      onPressed: _loadChannels,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: _buildBody(),
              ),
              _buildChannelNumberOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return _buildError();
    }

    if (_isFullScreen) {
      return Stack(
        children: [
          Positioned.fill(
            child: VideoPanel(
              channel: _selectedChannel,
              isFullScreen: true,
              onToggleFullScreen: _toggleFullScreen,
            ),
          ),
          _buildTvBoxHint(),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Row(
            children: [
              SizedBox(
                width: 330,
                child: ChannelList(
                  channels: _channels,
                  selectedChannel: _selectedChannel,
                  scrollController: _scrollController,
                  onChannelSelected: _selectChannel,
                ),
              ),
              Expanded(
                child: VideoPanel(
                  channel: _selectedChannel,
                  isFullScreen: false,
                  onToggleFullScreen: _toggleFullScreen,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              flex: 5,
              child: VideoPanel(
                channel: _selectedChannel,
                isFullScreen: false,
                onToggleFullScreen: _toggleFullScreen,
              ),
            ),
            Expanded(
              flex: 4,
              child: ChannelList(
                channels: _channels,
                selectedChannel: _selectedChannel,
                scrollController: _scrollController,
                onChannelSelected: _selectChannel,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChannelNumberOverlay() {
    if (!_showChannelNumberOverlay || _typedChannelNumber.isEmpty) {
      return const SizedBox.shrink();
    }

    final title = _channelNumberNotFound
        ? 'Canal no disponible'
        : 'Canal $_typedChannelNumber';

    return Positioned(
      top: _isFullScreen ? 24 : 86,
      right: 22,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _showChannelNumberOverlay ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 150,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: _channelNumberNotFound
                  ? Colors.redAccent.withValues(alpha: 0.92)
                  : Colors.black.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _typedChannelNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvBoxHint() {
    return Positioned(
      left: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '↑ ↓ cambiar canal  ·  números: canal directo  ·  OK pantalla completa  ·  ← volver',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off,
              color: Colors.redAccent,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadChannels,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}