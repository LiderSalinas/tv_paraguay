import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';

class ResolvedStream {
  const ResolvedStream(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
}

class StreamResolutionException implements Exception {
  const StreamResolutionException(
    this.message, {
    this.retryable = false,
    this.statusCode,
  });

  final String message;
  final bool retryable;
  final int? statusCode;

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
    'www.snt.com.py',
    'snt.com.py',
    'www.c9n.com.py',
    'c9n.com.py',
  };

  static const _broadcastPages = {
    'www.snt.com.py', 'snt.com.py', 'www.c9n.com.py', 'c9n.com.py',
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
      final body = _decode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
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
        final broadcast = _broadcastPages.contains(publisher.host) &&
            _isBroadcastCdn(uri);
        if (!uri.host.endsWith('.desdeparaguay.net') &&
            uri.host != 'video.hostingcaaguazu.com' && !broadcast) {
          continue;
        }
        final headers = {
          ...channel.httpHeaders,
          'User-Agent': _userAgent,
          'Referer': page.toString(),
          'Origin': page.origin,
        };
        if (broadcast) return _broadcastStream(uri, headers);
        return ResolvedStream(uri, headers);
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

  static bool _isBroadcastCdn(Uri uri) =>
      uri.scheme == 'https' && uri.host.endsWith('.cloudfront.net');

  Future<ResolvedStream> _broadcastStream(
    Uri master,
    Map<String, String> headers,
  ) async {
    final response = await _get(
      master, referer: headers['Referer']!, refresh: false,
    );
    final manifest = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!manifest.contains('#EXTM3U')) {
      throw const StreamResolutionException(
        'El proveedor no publicó una lista HLS válida.', retryable: true,
      );
    }
    if (!manifest.contains('#EXT-X-CONTENT-STEERING:')) {
      return ResolvedStream(master, headers);
    }

    // Older TV Box players cannot select HLS content-steering pathways.
    // Follow the default pathway published in the master and keep a declared
    // alternate for transport failures, without changing provider restrictions.
    final lines = manifest.split('\n').map((line) => line.trim()).toList();
    final steering = lines.firstWhere(
      (line) => line.startsWith('#EXT-X-CONTENT-STEERING:'),
    );
    final pathwayPattern = RegExp(r'''PATHWAY-ID="([^"]+)"''');
    final preferred = pathwayPattern.firstMatch(steering)?.group(1);
    final routes = <String, List<_HlsVariant>>{};
    var info = '';
    for (final line in lines) {
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        info = line;
      } else if (line.isNotEmpty && !line.startsWith('#') && info.isNotEmpty) {
        final height = int.tryParse(
          RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(info)?.group(1) ?? '',
        );
        final pathway = pathwayPattern.firstMatch(info)?.group(1) ?? '';
        final uri = master.resolve(line);
        if (height != null && height > 0 && _isBroadcastCdn(uri)) {
          routes.putIfAbsent(pathway, () => []).add(_HlsVariant(uri, height));
        }
        info = '';
      }
    }
    final order = [
      if (routes.containsKey(preferred)) preferred!,
      ...routes.keys.where((pathway) => pathway != preferred),
    ];
    StreamResolutionException? lastError;
    for (final pathway in order.take(3)) {
      final variants = routes[pathway]!..sort((a, b) => a.height.compareTo(b.height));
      final selected = variants.lastWhere(
        (variant) => variant.height <= 720, orElse: () => variants.first,
      );
      try {
        final media = await _get(
          selected.uri, referer: headers['Referer']!, refresh: false,
        );
        final text = utf8.decode(media.bodyBytes, allowMalformed: true);
        if (!text.contains('#EXTM3U') || !text.contains('#EXTINF:') ||
            text.contains('#EXT-X-ENDLIST')) {
          throw const StreamResolutionException(
            'La ruta del proveedor no tiene una señal en vivo.', retryable: true,
          );
        }
        return ResolvedStream(selected.uri, headers);
      } on StreamResolutionException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) rethrow;
        lastError = error;
      }
    }
    throw StreamResolutionException(
      lastError?.message ?? 'No se pudo conectar con una ruta del canal. Reintentá.',
      retryable: true,
      statusCode: lastError?.statusCode,
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
        statusCode: response.statusCode,
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

  static String _decode(String value) {
    var decoded = value;
    // Some publishers embed JSON in a JavaScript string, escaping it twice.
    for (var layer = 0; layer < 3; layer++) {
      final next = decoded
          .replaceAll('&amp;', '&')
          .replaceAll('&#38;', '&')
          .replaceAll(r'\u0026', '&')
          .replaceAll(r'\/', '/');
      if (next == decoded) break;
      decoded = next;
    }
    return decoded;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _HlsVariant {
  const _HlsVariant(this.uri, this.height);

  final Uri uri;
  final int height;
}
