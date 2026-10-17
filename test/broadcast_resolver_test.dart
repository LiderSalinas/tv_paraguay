import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/models/channel.dart';
import 'package:tv_paraguay/services/stream_resolver.dart';

Channel _channel(String page) => Channel.fromJson({
  'id': page.contains('snt') ? 3 : 5,
  'name': 'Canal',
  'streamUrl': 'https://old.cloudfront.net/expired.m3u8',
  'webUrl': page,
  'httpHeaders': {'X-Existing': 'preserve'},
});

String _page(String url) => jsonEncode(jsonEncode({'streamUrl': url}))
    .replaceAll('/', r'\\/');

const _media = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nlive.ts\n';
const _master = '''#EXTM3U
#EXT-X-CONTENT-STEERING:SERVER-URI="/steering/live.json",PATHWAY-ID="primary"
#EXT-X-STREAM-INF:BANDWIDTH=2900000,RESOLUTION=1280x720,PATHWAY-ID="backup"
https://backup.cloudfront.net/live/720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360,PATHWAY-ID="primary"
https://primary.cloudfront.net/live/360.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,PATHWAY-ID="primary"
https://primary.cloudfront.net/live/720.m3u8
''';

void main() {
  for (final page in ['https://www.snt.com.py/envivo/', 'https://www.c9n.com.py/envivo/']) {
    test('$page discovers escaped JSON and refreshes the source on each call', () async {
      var pages = 0;
      final resolver = StreamResolver(client: MockClient((request) async {
        if (request.url.host == Uri.parse(page).host) {
          pages++;
          expect(request.url.queryParameters, contains('_refresh'));
          return http.Response(_page('https://router.cloudfront.net/live-$pages/master.m3u8'), 200);
        }
        expect(request.headers['Referer'], page);
        return http.Response('#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1280x720\n720.m3u8\n', 200);
      }));
      final input = _channel(page);
      expect(resolver.needsRenewal(input), isTrue);
      final first = await resolver.resolve(input);
      final second = await resolver.resolve(input);
      expect(first.uri.path, '/live-1/master.m3u8');
      expect(second.uri.path, '/live-2/master.m3u8');
      expect(second.headers['X-Existing'], 'preserve');
      expect(second.headers['Origin'], Uri.parse(page).origin);
      expect(pages, 2);
    });
  }

  test('steering selects the published default pathway at 720p', () async {
    final requests = <Uri>[];
    final resolver = StreamResolver(client: MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'www.snt.com.py') {
        return http.Response(_page('https://router.cloudfront.net/master.m3u8'), 200);
      }
      return http.Response(request.url.host == 'router.cloudfront.net' ? _master : _media, 200);
    }));
    final stream = await resolver.resolve(_channel('https://www.snt.com.py/envivo/'));
    expect(stream.uri.toString(), 'https://primary.cloudfront.net/live/720.m3u8');
    expect(requests.length, 3);
    expect(requests.any((uri) => uri.host == 'backup.cloudfront.net'), isFalse);
  });

  test('a transport outage uses an alternate declared in the same master', () async {
    final resolver = StreamResolver(client: MockClient((request) async {
      if (request.url.host == 'www.c9n.com.py') {
        return http.Response(_page('https://router.cloudfront.net/master.m3u8'), 200);
      }
      if (request.url.host == 'router.cloudfront.net') return http.Response(_master, 200);
      if (request.url.host == 'primary.cloudfront.net') return http.Response('Unavailable', 503);
      return http.Response(_media, 200);
    }));
    final stream = await resolver.resolve(_channel('https://www.c9n.com.py/envivo/'));
    expect(stream.uri.host, 'backup.cloudfront.net');
  });

  test('authorization failures stop without trying an alternate pathway', () async {
    for (final status in [401, 403]) {
      var backupCalls = 0;
      final resolver = StreamResolver(client: MockClient((request) async {
        if (request.url.host == 'www.snt.com.py') {
          return http.Response(_page('https://router.cloudfront.net/master.m3u8'), 200);
        }
        if (request.url.host == 'router.cloudfront.net') return http.Response(_master, 200);
        if (request.url.host == 'backup.cloudfront.net') backupCalls++;
        return http.Response('Forbidden', status);
      }));
      await expectLater(
        resolver.resolve(_channel('https://www.snt.com.py/envivo/')),
        throwsA(isA<StreamResolutionException>()
            .having((error) => error.statusCode, 'status', status)
            .having((error) => error.retryable, 'retryable', isFalse)),
      );
      expect(backupCalls, 0);
    }
  });

  test('a finished or invalid playlist is not accepted as a live pathway', () async {
    final resolver = StreamResolver(client: MockClient((request) async {
      if (request.url.host == 'www.snt.com.py') {
        return http.Response(_page('https://router.cloudfront.net/master.m3u8'), 200);
      }
      if (request.url.host == 'router.cloudfront.net') return http.Response(_master, 200);
      return http.Response('$_media#EXT-X-ENDLIST\n', 200);
    }));
    await expectLater(
      resolver.resolve(_channel('https://www.snt.com.py/envivo/')),
      throwsA(isA<StreamResolutionException>().having((error) => error.retryable, 'retryable', isTrue)),
    );
  });

  test('CloudFront discovery is restricted to the SNT and C9N publishers', () async {
    var calls = 0;
    final resolver = StreamResolver(client: MockClient((_) async {
      calls++;
      return http.Response(_page('https://unrelated.cloudfront.net/master.m3u8'), 200);
    }));
    await expectLater(
      resolver.resolve(_channel('https://www.gen.com.py/')),
      throwsA(isA<StreamResolutionException>()),
    );
    expect(calls, 1);
  });
}
