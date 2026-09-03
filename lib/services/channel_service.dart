import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';

enum ChannelListSource { remote, local }

class ChannelLoadResult {
  const ChannelLoadResult({
    required this.channels,
    required this.source,
    this.warning,
  });

  final List<Channel> channels;
  final ChannelListSource source;
  final String? warning;

  bool get isRemote => source == ChannelListSource.remote;
}

class ChannelService {
  static const String _localAssetPath = 'canales.json';

  static const List<String> _remoteChannelsUrls = [
    'https://raw.githubusercontent.com/LiderSalinas/tv-paraguay-data/main/canales.json',
    'https://cdn.jsdelivr.net/gh/LiderSalinas/tv-paraguay-data@main/canales.json',
  ];

  Future<ChannelLoadResult> getChannels() async {
    Object? lastRemoteError;

    for (final remoteUrl in _remoteChannelsUrls) {
      try {
        final channels = await _loadRemoteChannels(remoteUrl);

        return ChannelLoadResult(
          channels: channels,
          source: ChannelListSource.remote,
        );
      } catch (error) {
        lastRemoteError = error;
      }
    }

    final localChannels = await _loadLocalChannels();

    return ChannelLoadResult(
      channels: localChannels,
      source: ChannelListSource.local,
      warning: lastRemoteError?.toString(),
    );
  }

  Future<List<Channel>> _loadRemoteChannels(String remoteUrl) async {
    final baseUri = Uri.parse(remoteUrl);
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        '_refresh': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('La lista remota respondió ${response.statusCode}');
    }

    return _decodeChannels(utf8.decode(response.bodyBytes));
  }

  Future<List<Channel>> _loadLocalChannels() async {
    final jsonString = await rootBundle.loadString(_localAssetPath);
    return _decodeChannels(jsonString);
  }

  List<Channel> _decodeChannels(String jsonString) {
    final decoded = jsonDecode(jsonString);

    if (decoded is! List) {
      throw Exception('El JSON de canales no tiene formato de lista');
    }

    final channels = decoded
        .map((item) => Channel.fromJson(Map<String, dynamic>.from(item)))
        .where(
          (channel) =>
              channel.isActive &&
              channel.isHls &&
              channel.streamUrl.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (channels.isEmpty) {
      throw Exception('La lista no contiene señales HLS activas');
    }

    return channels;
  }
}
