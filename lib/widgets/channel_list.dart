import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/playback_status.dart';
import '../theme/app_theme.dart';

class ChannelList extends StatelessWidget {
  final List<Channel> channels;
  final Channel? selectedChannel;
  final ValueChanged<Channel> onChannelSelected;
  final ScrollController? scrollController;
  final int? focusedChannelId;
  final PlaybackStatus playbackStatus;
  final bool largeText;
  final bool compact;

  const ChannelList({
    super.key,
    required this.channels,
    required this.selectedChannel,
    required this.onChannelSelected,
    this.scrollController,
    this.focusedChannelId,
    this.playbackStatus = PlaybackStatus.idle,
    this.largeText = false,
    this.compact = false,
  });

  static double rowExtent(BuildContext context, {bool largeText = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    final nameHeight = scaler.scale(largeText ? 22 : 18.5) * 2 * 1.2;
    final statusHeight = scaler.scale(12) * 1.25;
    return math.max(76, nameHeight + statusHeight + 22) + 8;
  }

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('No hay canales disponibles'));
    }
    final extent = rowExtent(context, largeText: largeText);
    return ListView.builder(
      key: const ValueKey('channel-list'),
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemExtent: extent,
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final selected = selectedChannel?.id == channel.id;
        final focused = focusedChannelId == channel.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            button: true,
            selected: selected,
            focused: focused,
            label: 'Canal ${channel.id}, ${channel.name}'
                '${selected ? ', ${playbackStatus.label}' : ''}',
            child: Material(
              color: selected ? AppColors.selected : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('channel-${channel.id}'),
                canRequestFocus: false,
                onTap: () => onChannelSelected(channel),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: focused
                          ? AppColors.focus
                          : selected
                              ? AppColors.blue.withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.07),
                      width: focused ? 3 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        color: selected ? AppColors.red : Colors.transparent,
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: math.max(largeText ? 36 : 30,
                            MediaQuery.textScalerOf(context).scale(largeText ? 22 : 19) * 1.4),
                        child: Text(
                          channel.id.toString().padLeft(2, '0'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: largeText ? 22 : 19,
                            fontWeight: FontWeight.w700,
                            color: selected ? AppColors.text : AppColors.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ChannelLogo(channel: channel, size: largeText ? 48 : 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              channel.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: largeText ? 22 : 18.5,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(height: 4),
                              Text(
                                playbackStatus.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  final Channel channel;
  final double size;
  const _ChannelLogo({required this.channel, required this.size});

  Widget get fallback {
    final name = channel.shortName.isEmpty ? channel.name : channel.shortName;
    final letters = name.isEmpty ? 'TV' : name.substring(0, math.min(4, name.length));
    return Center(
      child: Text(
        letters,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.background,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
        ),
        child: channel.logoUrl.trim().isEmpty
            ? fallback
            : Image.network(
                channel.logoUrl,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => fallback,
              ),
      );
}
