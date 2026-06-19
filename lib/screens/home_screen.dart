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
  bool _showHint = true;

  String _errorMessage = '';
  String _typedChannelNumber = '';

  Timer? _hintTimer;
  Timer? _numberTimer;

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
    _showTemporaryHint();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tvFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _numberTimer?.cancel();
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
      _showTemporaryHint();
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

  void _showTemporaryHint() {
    _hintTimer?.cancel();

    if (mounted) {
      setState(() {
        _showHint = true;
      });
    }

    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;

      setState(() {
        _showHint = false;
      });
    });
  }

  void _selectChannel(Channel channel) {
    setState(() {
      _selectedChannel = channel;
      _typedChannelNumber = '';
    });

    final index = _channels.indexWhere((item) => item.id == channel.id);
    if (index >= 0) {
      _scrollToSelected(index);
    }

    _requestTvFocus();
    _showTemporaryHint();
  }

  void _selectChannelByIndex(int index) {
    if (_channels.isEmpty) return;

    final safeIndex = index.clamp(0, _channels.length - 1);
    final channel = _channels[safeIndex];

    setState(() {
      _selectedChannel = channel;
      _typedChannelNumber = '';
    });

    _scrollToSelected(safeIndex);
    _requestTvFocus();
    _showTemporaryHint();
  }

  void _selectChannelByNumber(int number) {
    if (_channels.isEmpty) return;

    final index = _channels.indexWhere((channel) => channel.id == number);

    if (index >= 0) {
      _selectChannelByIndex(index);
      return;
    }

    setState(() {
      _typedChannelNumber = '';
    });

    _showTemporaryHint();
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

    const itemHeight = 86.0;
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
      _typedChannelNumber = '';
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
    _showTemporaryHint();
  }

  Future<void> _enterFullScreen() async {
    if (_isFullScreen) return;
    await _toggleFullScreen();
  }

  Future<void> _exitFullScreen() async {
    if (!_isFullScreen) return;
    await _toggleFullScreen();
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    final label = key.keyLabel;

    if (label.length == 1) {
      final digit = int.tryParse(label);
      if (digit != null) return digit;
    }

    final keyId = key.keyId;

    const digit0 = 0x0000000000000030;
    const digit9 = 0x0000000000000039;
    const numpad0 = 0x0000000000200030;
    const numpad9 = 0x0000000000200039;

    if (keyId >= digit0 && keyId <= digit9) {
      return keyId - digit0;
    }

    if (keyId >= numpad0 && keyId <= numpad9) {
      return keyId - numpad0;
    }

    return null;
  }

  void _handleDigit(int digit) {
    _numberTimer?.cancel();

    final nextValue = (_typedChannelNumber + digit.toString()).trim();

    setState(() {
      _typedChannelNumber = nextValue.length > 2
          ? digit.toString()
          : nextValue;
    });

    _showTemporaryHint();

    _numberTimer = Timer(const Duration(milliseconds: 900), () {
      final number = int.tryParse(_typedChannelNumber);
      if (number == null) return;

      _selectChannelByNumber(number);
    });
  }

  void _confirmTypedNumber() {
    if (_typedChannelNumber.isEmpty) return;

    _numberTimer?.cancel();

    final number = int.tryParse(_typedChannelNumber);
    if (number == null) return;

    _selectChannelByNumber(number);
  }

  KeyEventResult _handleTvRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final digit = _digitFromKey(key);

    if (digit != null) {
      _handleDigit(digit);
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
        _confirmTypedNumber();
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
      if (_isFullScreen) {
        _exitFullScreen();
        return KeyEventResult.handled;
      }

      _showTemporaryHint();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      if (_typedChannelNumber.isNotEmpty) {
        setState(() {
          _typedChannelNumber = '';
        });
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
        onTap: () {
          _requestTvFocus();
          _showTemporaryHint();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.redAccent,
        ),
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
          if (_showHint) _buildTvBoxHint(),
          if (_typedChannelNumber.isNotEmpty) _buildTypedNumberOverlay(),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        return Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: isWide
                      ? _buildWideLayout(constraints)
                      : _buildMobileLayout(),
                ),
              ],
            ),
            if (_showHint) _buildTvBoxHint(),
            if (_typedChannelNumber.isNotEmpty) _buildTypedNumberOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'TV Paraguay',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar canales',
            onPressed: _loadChannels,
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
              size: 31,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(BoxConstraints constraints) {
    final sidebarWidth = constraints.maxWidth >= 1200 ? 320.0 : 300.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 72),
      child: Row(
        children: [
          SizedBox(
            width: sidebarWidth,
            child: ChannelList(
              channels: _channels,
              selectedChannel: _selectedChannel,
              scrollController: _scrollController,
              onChannelSelected: _selectChannel,
              compact: true,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: VideoPanel(
                channel: _selectedChannel,
                isFullScreen: false,
                onToggleFullScreen: _toggleFullScreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 82),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: VideoPanel(
                channel: _selectedChannel,
                isFullScreen: false,
                onToggleFullScreen: _toggleFullScreen,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ChannelList(
              channels: _channels,
              selectedChannel: _selectedChannel,
              scrollController: _scrollController,
              onChannelSelected: _selectChannel,
              compact: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvBoxHint() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 18,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(20, 20, 20, 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color.fromRGBO(255, 255, 255, 0.10),
            ),
          ),
          child: const Text(
            '↑↓ cambiar canal  ·  OK pantalla completa  ·  0-9 canal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypedNumberOverlay() {
    return Positioned(
      left: 24,
      top: 96,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(0, 0, 0, 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.redAccent,
            width: 1.5,
          ),
        ),
        child: Text(
          _typedChannelNumber.padLeft(2, '0'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w900,
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
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
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