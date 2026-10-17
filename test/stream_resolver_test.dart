import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/models/channel.dart';
import 'package:tv_paraguay/services/stream_resolver.dart';

Channel channel({
  String page = '',
  String stream = 'https://cdn.example/live.m3u8',
}) => Channel.fromJson({
  'id': 15,
  'name': 'Canal',
  'streamUrl': stream,
  'webUrl': page,
  'httpHeaders': {'Referer': 'https://publisher.example/'},
});

String dmPage({String host = 'geo.dailymotion.com'}) =>
    '<iframe src="https://$host/player/x1b1gw.html?video=kCurrentVideo&amp;mute=false"></iframe>';

Map<String, Object?> metadata({
  Object? error,
  bool password = false,
  String mode = 'live',
  String type = 'application/x-mpegURL',
  String url =
      'https://cdndirector.dailymotion.com/live/channel.m3u8?sec=fresh',
}) => {
  'mode': mode,
  'error': error,
  'is_password_protected': password,
  'qualities': {
    'auto': [
      {'type': type, 'url': url},
    ],
  },
};

void main() {
  test(
    'a direct sports channel keeps its URL and makes no resolver requests',
    () async {
      final resolver = StreamResolver(
        client: MockClient((_) async => throw StateError('unexpected request')),
      );
      final input = channel();
      final stream = await resolver.resolve(input);
      expect(stream.uri.toString(), input.streamUrl);
      expect(stream.headers, input.httpHeaders);
      expect(resolver.needsRenewal(input), isFalse);
    },
  );

  test(
    'GEN uses a new issuer URL on every selection, including delivery headers',
    () async {
      var calls = 0;
      final resolver = StreamResolver(
        client: MockClient((request) async {
          calls++;
          expect(request.url.queryParameters, contains('_refresh'));
          expect(request.headers['Cache-Control'], contains('no-cache'));
          expect(request.headers['Referer'], 'https://www.gen.com.py/');
          return http.Response(
            "source: 'https://rds3gen.desdeparaguay.net/gentv/playlist.m3u8?k=token$calls&exp=123'",
            200,
          );
        }),
      );
      final input = channel(
        page: 'https://gentv.desdepylabs.com/External/gentv',
        stream: 'https://old.example/expired.m3u8',
      );
      final first = await resolver.resolve(input);
      final second = await resolver.resolve(input);
      expect(calls, 2);
      expect(first.uri.queryParameters['k'], 'token1');
      expect(second.uri.queryParameters['k'], 'token2');
      expect(second.headers['Origin'], 'https://gentv.desdepylabs.com');
      expect(second.headers['Referer'], input.webUrl);
    },
  );

  test(
    'GEN follows the current official iframe and skips the expired-session slate',
    () async {
      final requests = <http.Request>[];
      final resolver = StreamResolver(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'www.gen.com.py') {
            return http.Response(
              '<iframe src="https://gentv.desdepylabs.com/External/gentv"></iframe>',
              200,
            );
          }
          return http.Response(
            "src: 'https://sesion.desdeparaguay.net/hls/playlist.m3u8'; src: 'https://rds3gen.desdeparaguay.net/gentv/playlist.m3u8?k=new&amp;exp=123'",
            200,
          );
        }),
      );
      final stream = await resolver.resolve(
        channel(page: 'https://www.gen.com.py/'),
      );
      expect(requests.length, 2);
      expect(requests.last.headers['Referer'], 'https://www.gen.com.py/');
      expect(stream.uri.host, 'rds3gen.desdeparaguay.net');
      expect(stream.uri.queryParameters['exp'], '123');
    },
  );

  test(
    'ABC reads the current video and player IDs, rather than the old saved HLS URL',
    () async {
      final resolver = StreamResolver(
        client: MockClient((request) async {
          if (request.url.host == 'www.abc.com.py') {
            return http.Response(dmPage(), 200);
          }
          expect(request.url.host, 'geo.dailymotion.com');
          expect(request.url.path, '/video/kCurrentVideo.json');
          expect(request.url.queryParameters['player-id'], 'x1b1gw');
          expect(
            request.url.queryParameters['embedder'],
            'https://www.abc.com.py/tv/',
          );
          expect(
            request.url.queryParameters.containsKey('no_ip_lock'),
            isFalse,
          );
          expect(request.url.queryParameters.containsKey('no_expire'), isFalse);
          return http.Response(jsonEncode(metadata()), 200);
        }),
      );
      final stream = await resolver.resolve(
        channel(page: 'https://www.abc.com.py/tv/'),
      );
      expect(stream.uri.queryParameters['sec'], 'fresh');
      expect(stream.headers['Origin'], 'https://geo.dailymotion.com');
    },
  );

  test(
    'Dailymotion playback information is fetched again for a second selection',
    () async {
      var calls = 0;
      final resolver = StreamResolver(
        client: MockClient((request) async {
          if (request.url.host == 'www.unicanal.com.py') {
            return http.Response(dmPage(), 200);
          }
          calls++;
          return http.Response(
            jsonEncode(
              metadata(
                url:
                    'https://cdndirector.dailymotion.com/live/channel.m3u8?sec=token$calls',
              ),
            ),
            200,
          );
        }),
      );
      final input = channel(page: 'https://www.unicanal.com.py/');
      expect(
        (await resolver.resolve(input)).uri.queryParameters['sec'],
        'token1',
      );
      expect(
        (await resolver.resolve(input)).uri.queryParameters['sec'],
        'token2',
      );
    },
  );

  test(
    'Trece preserves a regional restriction and does not fall back to an expired stream',
    () async {
      final resolver = StreamResolver(
        client: MockClient((request) async {
          if (request.url.host == 'www.trece.com.py') {
            return http.Response(dmPage(), 200);
          }
          return http.Response(
            jsonEncode(metadata(error: {'code': 'DM007'})),
            200,
          );
        }),
      );
      await expectLater(
        resolver.resolve(channel(page: 'https://www.trece.com.py/')),
        throwsA(
          isA<StreamResolutionException>()
              .having((e) => e.message, 'message', contains('región'))
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    },
  );

  test(
    'provider authorization errors and protected content never expose a playback URL',
    () async {
      for (final result in [
        metadata(error: {'code': 'DM016'}),
        metadata(password: true),
      ]) {
        final resolver = StreamResolver(
          client: MockClient(
            (request) async =>
                request.url.host == 'www.abc.com.py'
                    ? http.Response(dmPage(), 200)
                    : http.Response(jsonEncode(result), 200),
          ),
        );
        await expectLater(
          resolver.resolve(channel(page: 'https://www.abc.com.py/tv/')),
          throwsA(isA<StreamResolutionException>()),
        );
      }
    },
  );

  test(
    'a VOD fallback or DASH-only source is not presented as a live HLS channel',
    () async {
      for (final result in [
        metadata(mode: 'vod'),
        metadata(type: 'application/dash+xml'),
      ]) {
        final resolver = StreamResolver(
          client: MockClient(
            (request) async =>
                request.url.host == 'www.abc.com.py'
                    ? http.Response(dmPage(), 200)
                    : http.Response(jsonEncode(result), 200),
          ),
        );
        await expectLater(
          resolver.resolve(channel(page: 'https://www.abc.com.py/tv/')),
          throwsA(isA<StreamResolutionException>()),
        );
      }
    },
  );

  test(
    'Oasis follows the provider iframe and discovers its current stream path',
    () async {
      final resolver = StreamResolver(
        client: MockClient((request) async {
          if (request.url.path == '/oasistv/') {
            return http.Response(
              '<iframe src="https://tvonline.com.py/tv/oasistv.html"></iframe>',
              200,
            );
          }
          return http.Response(
            'source: "https://video.hostingcaaguazu.com:19360/new-oasis/channel.m3u8"',
            200,
          );
        }),
      );
      final stream = await resolver.resolve(
        channel(page: 'https://tvonline.com.py/oasistv/'),
      );
      expect(stream.uri.path, '/new-oasis/channel.m3u8');
      expect(
        stream.headers['Referer'],
        'https://tvonline.com.py/tv/oasistv.html',
      );
    },
  );

  test(
    'a provider 404 is reported without inventing a replacement signal',
    () async {
      final resolver = StreamResolver(
        client: MockClient((_) async => http.Response('Not found', 404)),
      );
      await expectLater(
        resolver.resolve(channel(page: 'https://tvonline.com.py/oasistv/')),
        throwsA(
          isA<StreamResolutionException>().having(
            (e) => e.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    },
  );

  test(
    'transient network failures are eligible for a bounded player retry',
    () async {
      final resolver = StreamResolver(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        resolver.resolve(channel(page: 'https://www.gen.com.py/')),
        throwsA(
          isA<StreamResolutionException>().having(
            (e) => e.retryable,
            'retryable',
            isTrue,
          ),
        ),
      );
    },
  );

  test('an iframe cycle stops after three page requests', () async {
    var calls = 0;
    final resolver = StreamResolver(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          '<iframe src="https://tvonline.com.py/oasistv/"></iframe>',
          200,
        );
      }),
    );
    await expectLater(
      resolver.resolve(channel(page: 'https://tvonline.com.py/oasistv/')),
      throwsA(isA<StreamResolutionException>()),
    );
    expect(calls, 3);
  });

  test('unexpected metadata hosts and media hosts are rejected', () async {
    final resolver = StreamResolver(
      client: MockClient(
        (request) async =>
            request.url.host == 'www.abc.com.py'
                ? http.Response(dmPage(), 200)
                : http.Response(
                  jsonEncode(metadata(url: 'https://evil.example/live.m3u8')),
                  200,
                ),
      ),
    );
    await expectLater(
      resolver.resolve(channel(page: 'https://www.abc.com.py/tv/')),
      throwsA(isA<StreamResolutionException>()),
    );
  });
}
