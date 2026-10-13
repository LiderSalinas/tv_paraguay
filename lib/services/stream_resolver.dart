import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

class ResolvedStream {
  const ResolvedStream(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}

class StreamResolutionException implements Exception {
  const StreamResolutionException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

/// Resolve public playback information on the viewer's device. Signed URLs
/// must never be shared between viewers or retained as permanent sources.
class StreamResolver {
  StreamResolver({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _now = now ?? DateTime.now;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  static const _userAgent = 'Mozilla/5.0';
  static const _pageHosts = {
    'www.abc.com.py',
    'abc.com.py',
    'www.trece.com.py',
    'trece.com.py',
    'www.unicanal.com.py',
    'unicanal.com.py',
    'www.gen.com.py',
    'gen.com.py',
    'gentv.desdepylabs.com',
    'tvonline.com.py',
    'www.tvonline.com.py',
  };

  bool needsRenewal(Channel channel) {
    final source = Uri.tryParse(channel.webUrl);
    return source != null &&
        source.scheme == 'https' &&
        _pageHosts.contains(source.host.toLowerCase());
  }

  Future<ResolvedStream> resolve(Channel channel) async {
    if (!needsRenewal(channel)) {
      return ResolvedStream(_streamUri(channel.streamUrl), channel.httpHeaders);
    }

    final publisher = Uri.parse(channel.webUrl);
    var page = publisher;
    var referer = publisher.toString();
    if (publisher.host == 'gentv.desdepylabs.com') {
      referer = 'https://www.gen.com.py/';
    }

    for (var depth = 0; depth < 3; depth++) {
      final response = await _get(page, referer: referer, refresh: true);
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final frames = RegExp(
        r'''<iframe\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).allMatches(body).map((match) => page.resolve(_decode(match[1]!)));

      for (final frame in frames) {
        if (frame.host == 'geo.dailymotion.com' &&
            frame.path.startsWith('/player/')) {
          return _dailymotion(frame, publisher, channel.httpHeaders);
        }
      }

      final sources = RegExp(
        r'''https?://[^\s"'<>\\]+\.m3u8[^\s"'<>\\]*''',
        caseSensitive: false,
      ).allMatches(body).map((match) => _decode(match[0]!));
      for (final source in sources) {
        final uri = _streamUri(source);
        if (uri.host == 'sesion.desdeparaguay.net') continue;
        if (!uri.host.endsWith('.desdeparaguay.net') &&
            uri.host != 'video.hostingcaaguazu.com') {
          continue;
        }
        return ResolvedStream(uri, {
          ...channel.httpHeaders,
          'User-Agent': _userAgent,
          'Referer': page.toString(),
          'Origin': page.origin,
        });
      }

      final next =
          frames
              .where(
                (frame) =>
                    frame.scheme == 'https' && _pageHosts.contains(frame.host),
              )
              .firstOrNull;
      if (next == null) break;
      referer = page.toString();
      page = next;
    }

    throw const StreamResolutionException(
      'El proveedor no publicó una señal HLS disponible. Reintentá más tarde.',
    );
  }

  Future<ResolvedStream> _dailymotion(
    Uri frame,
    Uri publisher,
    Map<String, String> originalHeaders,
  ) async {
    final video = frame.queryParameters['video'];
    final player = RegExp(
      r'^([a-zA-Z0-9]+)\.html$',
    ).firstMatch(frame.pathSegments.lastOrNull ?? '')?.group(1);
    if (video == null ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(video) ||
        player == null) {
      throw const StreamResolutionException('El reproductor del canal cambió.');
    }

    // Use the public metadata endpoint selected by the publisher's own player.
    // No private API keys, geo overrides or delivery restrictions are changed.
    final uri = Uri.https('geo.dailymotion.com', '/video/$video.json', {
      'legacy': 'true',
      'player-id': player,
      'embedder': publisher.toString(),
      'referer': publisher.toString(),
      'geo': '1',
      'locale': 'es',
    });
    final response = await _get(uri, referer: frame.toString(), refresh: true);
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const StreamResolutionException(
        'El proveedor devolvió una respuesta inválida.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const StreamResolutionException(
        'El proveedor devolvió una respuesta inválida.',
      );
    }

    final error = decoded['error'];
    if (error != null) {
      if (error is Map && error['code'] == 'DM007') {
        throw const StreamResolutionException(
          'El proveedor restringe esta señal por región.',
        );
      }
      throw const StreamResolutionException(
        'El proveedor no habilitó esta señal para reproducirla.',
      );
    }
    if (decoded['is_password_protected'] == true) {
      throw const StreamResolutionException(
        'Esta señal requiere acceso autorizado del proveedor.',
      );
    }
    if (decoded['mode'] != 'live') {
      throw const StreamResolutionException(
        'El canal no está transmitiendo en vivo.',
      );
    }

    final qualities = decoded['qualities'];
    if (qualities is Map) {
      for (final entries in qualities.values) {
        if (entries is! List) continue;
        for (final entry in entries) {
          if (entry is! Map || entry['url'] is! String) continue;
          final type = (entry['type'] as String? ?? '').toLowerCase();
          if (type != 'application/x-mpegurl' &&
              type != 'application/vnd.apple.mpegurl') {
            continue;
          }
          final stream = _streamUri(entry['url'] as String);
          if (!stream.host.endsWith('.dailymotion.com') &&
              !stream.host.endsWith('.dmcdn.net')) {
            continue;
          }
          return ResolvedStream(stream, {
            ...originalHeaders,
            'User-Agent': _userAgent,
            'Referer': publisher.toString(),
            'Origin': 'https://geo.dailymotion.com',
          });
        }
      }
    }
    throw const StreamResolutionException(
      'El proveedor no publicó una señal HLS disponible.',
    );
  }

  Future<http.Response> _get(
    Uri uri, {
    required String referer,
    required bool refresh,
  }) async {
    final requestUri =
        refresh
            ? uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                '_refresh': _now().millisecondsSinceEpoch.toString(),
              },
            )
            : uri;
    http.Response response;
    try {
      response = await _client
          .get(
            requestUri,
            headers: {
              'User-Agent': _userAgent,
              'Referer': referer,
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const StreamResolutionException(
        'No se pudo conectar con el proveedor. Reintentá.',
        retryable: true,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StreamResolutionException(
        'La señal del proveedor no está disponible. Reintentá más tarde.',
        retryable: response.statusCode >= 500,
      );
    }
    if (response.bodyBytes.length > 2000000) {
      throw const StreamResolutionException(
        'El proveedor devolvió una respuesta inesperada.',
      );
    }
    return response;
  }

  static Uri _streamUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const StreamResolutionException(
        'El canal no tiene una dirección de video válida.',
      );
    }
    return uri;
  }

  static String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&#38;', '&')
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\/', '/');

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
