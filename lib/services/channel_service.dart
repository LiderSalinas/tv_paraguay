import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';

enum ChannelListSource { remote, cached, bundled }

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

abstract class ChannelListCache {
  Future<String?> read();

  Future<void> write(String jsonString);

  Future<void> clear();
}

class PlatformChannelListCache implements ChannelListCache {
  static const MethodChannel _channel = MethodChannel(
    'tv_paraguay/channel_list_cache',
  );
  static const Duration _operationTimeout = Duration(seconds: 3);

  @override
  Future<String?> read() =>
      _channel.invokeMethod<String>('read').timeout(_operationTimeout);

  @override
  Future<void> write(String jsonString) => _channel
      .invokeMethod<void>('write', {'json': jsonString})
      .timeout(_operationTimeout);

  @override
  Future<void> clear() =>
      _channel.invokeMethod<void>('clear').timeout(_operationTimeout);
}

class ChannelService {
  ChannelService({
    http.Client? httpClient,
    ChannelListCache? cache,
    Future<String> Function()? assetLoader,
    List<String>? remoteUrls,
    DateTime Function()? clock,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _cache = cache ?? PlatformChannelListCache(),
       _assetLoader =
           assetLoader ?? (() => rootBundle.loadString(_localAssetPath)),
       _remoteUrls = List.unmodifiable(
         remoteUrls ?? _defaultRemoteChannelsUrls,
       ),
       _clock = clock ?? DateTime.now;

  static const String _localAssetPath = 'canales.json';

  static const List<String> _defaultRemoteChannelsUrls = [
    'https://raw.githubusercontent.com/LiderSalinas/tv-paraguay-data/main/canales.json',
    'https://cdn.jsdelivr.net/gh/LiderSalinas/tv-paraguay-data@main/canales.json',
  ];

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final ChannelListCache _cache;
  final Future<String> Function() _assetLoader;
  final List<String> _remoteUrls;
  final DateTime Function() _clock;

  Future<ChannelLoadResult> getChannels() async {
    final warnings = <String>[];

    for (final remoteUrl in _remoteUrls) {
      try {
        final jsonString = await _downloadRemoteJson(remoteUrl);
        final channels = _decodeChannels(jsonString);

        try {
          await _cache.write(jsonString);
        } catch (error) {
          warnings.add('No se pudo guardar la copia remota: $error');
        }

        return ChannelLoadResult(
          channels: channels,
          source: ChannelListSource.remote,
          warning: _joinWarnings(warnings),
        );
      } catch (error) {
        warnings.add('Falló $remoteUrl: $error');
      }
    }

    try {
      final cachedJson = await _cache.read();

      if (cachedJson != null && cachedJson.trim().isNotEmpty) {
        try {
          return ChannelLoadResult(
            channels: _decodeChannels(cachedJson),
            source: ChannelListSource.cached,
            warning: _joinWarnings(warnings),
          );
        } catch (error) {
          warnings.add('La última copia guardada no es válida: $error');
          await _clearInvalidCache(warnings);
        }
      }
    } catch (error) {
      warnings.add('No se pudo leer la última copia guardada: $error');
    }

    final bundledJson = await _assetLoader();

    return ChannelLoadResult(
      channels: _decodeChannels(bundledJson),
      source: ChannelListSource.bundled,
      warning: _joinWarnings(warnings),
    );
  }

  Future<String> _downloadRemoteJson(String remoteUrl) async {
    final baseUri = Uri.parse(remoteUrl);
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        '_refresh': _clock().microsecondsSinceEpoch.toString(),
      },
    );

    final response = await _httpClient
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

    return utf8.decode(response.bodyBytes);
  }

  Future<void> _clearInvalidCache(List<String> warnings) async {
    try {
      await _cache.clear();
    } catch (error) {
      warnings.add('No se pudo descartar la copia inválida: $error');
    }
  }

  List<Channel> _decodeChannels(String jsonString) {
    final decoded = jsonDecode(jsonString);

    if (decoded is! List) {
      throw const FormatException(
        'El JSON de canales no tiene formato de lista',
      );
    }

    final channels =
        decoded
            .map((item) {
              if (item is! Map) {
                throw const FormatException(
                  'Hay un canal con formato inválido',
                );
              }

              return Channel.fromJson(Map<String, dynamic>.from(item));
            })
            .where(_isSupportedChannel)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    if (channels.isEmpty) {
      throw const FormatException('La lista no contiene canales compatibles');
    }

    final uniqueIds = channels.map((channel) => channel.id).toSet();
    if (uniqueIds.length != channels.length) {
      throw const FormatException(
        'La lista contiene números de canal repetidos',
      );
    }

    return channels;
  }

  bool _isSupportedChannel(Channel channel) {
    if (!channel.isActive || channel.name.trim().isEmpty) {
      return false;
    }

    if (channel.isExternalApp) {
      return channel.externalPackage.trim().isNotEmpty;
    }

    if (!channel.isHls || channel.streamUrl.trim().isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(channel.streamUrl);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }

    return uri.path.toLowerCase().endsWith('.m3u8');
  }

  String? _joinWarnings(List<String> warnings) {
    if (warnings.isEmpty) return null;
    return warnings.join(' | ');
  }

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}
