import 'package:flutter/material.dart';

import '../models/channel.dart';

class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final Channel? selectedChannel;
  final ValueChanged<Channel> onChannelSelected;
  final ScrollController? scrollController;
  final bool compact;

  const ChannelList({
    super.key,
    required this.channels,
    required this.selectedChannel,
    required this.onChannelSelected,
    this.scrollController,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(
        child: Text(
          'No hay canales disponibles',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: channels.length,
      separatorBuilder: (_, __) => SizedBox(height: compact ? 8 : 12),
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isSelected = selectedChannel?.id == channel.id;

        return _ChannelTile(
          channel: channel,
          isSelected: isSelected,
          compact: compact,
          onTap: () => onChannelSelected(channel),
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.isSelected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final channelNumber = channel.id.toString().padLeft(2, '0');

    final tileHeight = compact ? 78.0 : 92.0;
    final numberWidth = compact ? 66.0 : 96.0;
    final logoSize = compact ? 50.0 : 68.0;
    final nameFontSize = compact ? 20.0 : 25.0;
    final playSize = compact ? 38.0 : 46.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: BoxConstraints(minHeight: tileHeight),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: isSelected
                ? const Color.fromRGBO(95, 12, 16, 0.92)
                : const Color.fromRGBO(22, 24, 28, 0.96),
            border: Border.all(
              color: isSelected
                  ? Colors.redAccent
                  : const Color.fromRGBO(255, 255, 255, 0.08),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color.fromRGBO(255, 50, 60, 0.26),
                      blurRadius: 14,
                      offset: Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: numberWidth,
                height: tileHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color.fromRGBO(190, 20, 28, 0.82)
                      : const Color.fromRGBO(10, 11, 13, 0.80),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                  border: const Border(
                    right: BorderSide(
                      color: Color.fromRGBO(255, 255, 255, 0.07),
                    ),
                  ),
                ),
                child: Text(
                  channelNumber,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 25 : 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              SizedBox(width: compact ? 12 : 18),
              _Logo(
                channel: channel,
                size: logoSize,
                compact: compact,
              ),
              SizedBox(width: compact ? 14 : 22),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: nameFontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PlayIndicator(
                isSelected: isSelected,
                size: playSize,
              ),
              SizedBox(width: compact ? 10 : 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final Channel channel;
  final double size;
  final bool compact;

  const _Logo({
    required this.channel,
    required this.size,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final logoUrl = channel.logoUrl.trim();

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(compact ? 5 : 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 11 : 14),
      ),
      child: logoUrl.isEmpty
          ? _FallbackLogo(channel: channel, compact: compact)
          : Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _FallbackLogo(
                channel: channel,
                compact: compact,
              ),
            ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  final Channel channel;
  final bool compact;

  const _FallbackLogo({
    required this.channel,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final text = channel.shortName.trim().isNotEmpty
        ? channel.shortName.trim()
        : channel.name.trim();

    return Center(
      child: Text(
        text.length > 4
            ? text.substring(0, 4).toUpperCase()
            : text.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black87,
          fontSize: compact ? 10 : 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PlayIndicator extends StatelessWidget {
  final bool isSelected;
  final double size;

  const _PlayIndicator({
    required this.isSelected,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? Colors.redAccent
            : const Color.fromRGBO(255, 255, 255, 0.16),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * 0.72,
      ),
    );
  }
}