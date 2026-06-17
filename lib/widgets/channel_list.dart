import 'package:flutter/material.dart';

import '../models/channel.dart';

class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final Channel? selectedChannel;
  final ValueChanged<Channel> onChannelSelected;
  final ScrollController? scrollController;

  const ChannelList({
    super.key,
    required this.channels,
    required this.selectedChannel,
    this.scrollController,
    ValueChanged<Channel>? onChannelSelected,
    ValueChanged<Channel>? onChannelTap,
  }) : onChannelSelected = onChannelSelected ?? onChannelTap ?? _emptyTap;

  static void _emptyTap(Channel channel) {}

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(
        child: Text(
          'No hay canales disponibles',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isSelected = selectedChannel?.id == channel.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ChannelCard(
            channel: channel,
            isSelected: isSelected,
            onTap: () => onChannelSelected(channel),
          ),
        );
      },
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected
        ? const Color(0xFFFF4655)
        : const Color(0xFF1E1E22);

    final borderColor = isSelected
        ? const Color(0xFFFF6B76)
        : Colors.white.withOpacity(0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        focusColor: const Color(0xFFFF4655).withOpacity(0.45),
        hoverColor: const Color(0xFFFF4655).withOpacity(0.18),
        splashColor: Colors.white.withOpacity(0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(
            minHeight: 86,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF4655).withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              _ChannelLogo(channel: channel),
              const SizedBox(width: 16),
              Expanded(
                child: _ChannelInfo(
                  channel: channel,
                  isSelected: isSelected,
                ),
              ),
              const SizedBox(width: 10),
              _PlayIcon(isSelected: isSelected),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  final Channel channel;

  const _ChannelLogo({
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    final logoUrl = channel.logoUrl.trim();
    final hasLogo = logoUrl.isNotEmpty;

    return Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: hasLogo
            ? Image.network(
                logoUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) {
                  return _ShortNameLogo(channel: channel);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return _ShortNameLogo(channel: channel);
                },
              )
            : _ShortNameLogo(channel: channel),
      ),
    );
  }
}

class _ShortNameLogo extends StatelessWidget {
  final Channel channel;

  const _ShortNameLogo({
    required this.channel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        channel.shortName,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ChannelInfo extends StatelessWidget {
  final Channel channel;
  final bool isSelected;

  const _ChannelInfo({
    required this.channel,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = isSelected
        ? Colors.white.withOpacity(0.88)
        : Colors.white70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          channel.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Flexible(
              child: Text(
                channel.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: categoryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PlayerBadge(
              label: channel.playerLabel,
              isSelected: isSelected,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _PlayerBadge({
    required this.label,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = isSelected
        ? Colors.black.withOpacity(0.22)
        : Colors.black.withOpacity(0.34);

    final textColor = isSelected ? Colors.white : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _PlayIcon extends StatelessWidget {
  final bool isSelected;

  const _PlayIcon({
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.play_circle_fill_rounded,
      color: isSelected
          ? Colors.white.withOpacity(0.82)
          : Colors.white54,
      size: 34,
    );
  }
}