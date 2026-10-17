import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/models/channel.dart';
import 'package:tv_paraguay/widgets/video_panel.dart';

import 'support/fake_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';


Channel gen() => Channel.fromJson({
  'id': 15,
  'name': 'GEN',
  'streamUrl': 'https://old.example/expired.m3u8',
  'webUrl': 'https://gentv.desdepylabs.com/External/gentv',
});

Widget screen(Channel channel) =>
    MaterialApp(home: VideoPanel(channel: channel));
String source(int number) =>
    "src: 'https://rds3gen.desdeparaguay.net/gentv/playlist.m3u8?k=token$number'";

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void main() {
  late VideoPlayerPlatform original;
  late FakePlayer fake;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    fake = FakePlayer();
    VideoPlayerPlatform.instance = fake;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = original;
  });

  testWidgets('an old channel response cannot replace the newer selection', (
    tester,
  ) async {
    final delayed = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(screen(gen()));
      await flush(tester);
      final sports = Channel.fromJson({
        'id': 24,
        'name': 'ESPN',
        'streamUrl': 'https://sports.example/live.m3u8',
      });
      await tester.pumpWidget(screen(sports));
      await flush(tester);
      expect(fake.sources, ['https://sports.example/live.m3u8']);
      delayed.complete(http.Response(source(1), 200));
      await flush(tester);
      expect(fake.sources, ['https://sports.example/live.m3u8']);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    }, () => MockClient((_) => delayed.future));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'background renewal retains the old player until the new URL is ready',
    (tester) async {
      final delayed = Completer<http.Response>();
      var calls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(screen(gen()));
          await flush(tester);
          expect(fake.played, [1]);
          final initialPauses = fake.paused.length;
          await tester.pump(const Duration(minutes: 5));
          await flush(tester);
          expect(calls, 2);
          expect(fake.disposed, isEmpty);
          expect(fake.paused.length, initialPauses);
          delayed.complete(http.Response(source(2), 200));
          await flush(tester);
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await flush(tester);
          expect(fake.sources.length, 2);
          expect(fake.played, [1, 2]);
          expect(fake.disposed, [1]);
          await tester.pumpWidget(const SizedBox.shrink());
          await flush(tester);
        },
        () => MockClient((_) async {
          calls++;
          return calls == 1 ? http.Response(source(1), 200) : delayed.future;
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two fast retries back off; manual retry resets the fast retry budget',
    (tester) async {
      var calls = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(screen(gen()));
          await flush(tester);
          await tester.pump(const Duration(seconds: 3));
          await flush(tester);
          await tester.pump(const Duration(seconds: 3));
          await flush(tester);
          await tester.pump(const Duration(seconds: 30));
          await flush(tester);
          expect(calls, 3);
          await tester.tap(find.text('Reintentar'));
          await flush(tester);
          expect(calls, 4);
          await tester.pumpWidget(const SizedBox.shrink());
          await flush(tester);
        },
        () => MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an unchanged renewed source keeps its working controller', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(screen(gen()));
      await flush(tester);
      final initialPauses = fake.paused.length;
      for (var renewal = 0; renewal < 2; renewal++) {
        await tester.pump(const Duration(minutes: 5));
        await flush(tester);
      }
      expect(calls, 3);
      expect(fake.sources.length, 1);
      expect(fake.played, [1]);
      expect(fake.paused.length, initialPauses);
      expect(fake.disposed, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    }, () => MockClient((_) async {
      calls++;
      return http.Response(source(1), 200);
    }));
    expect(tester.takeException(), isNull);
  });

  testWidgets('transient failures keep retrying slowly and stop on dispose', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(screen(gen()));
      await flush(tester);
      await tester.pump(const Duration(seconds: 3));
      await flush(tester);
      await tester.pump(const Duration(seconds: 3));
      await flush(tester);
      expect(calls, 3);
      await tester.pump(const Duration(seconds: 59));
      await flush(tester);
      expect(calls, 3);
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(calls, 4);
      await tester.tap(find.text('Reintentar'));
      await flush(tester);
      expect(calls, 5);
      await tester.pump(const Duration(seconds: 3));
      await flush(tester);
      expect(calls, 6);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 6);
    }, () => MockClient((_) async {
      calls++;
      throw http.ClientException('offline');
    }));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a regional restriction does not schedule periodic retries', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      final abc = Channel.fromJson({
        'id': 16, 'name': 'ABC Digital',
        'streamUrl': 'https://old.example/expired.m3u8',
        'webUrl': 'https://www.abc.com.py/tv/',
      });
      await tester.pumpWidget(screen(abc));
      await flush(tester);
      await tester.pump(const Duration(minutes: 2));
      await flush(tester);
      expect(calls, 2);
      expect(fake.sources, isEmpty);
      expect(find.textContaining('región'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    }, () => MockClient((request) async {
      calls++;
      if (request.url.host == 'www.abc.com.py') {
        return http.Response('<iframe src="https://geo.dailymotion.com/player/x1b1gw.html?video=kLive"></iframe>', 200);
      }
      return http.Response('{"error":{"code":"DM007"}}', 200);
    }));
    expect(tester.takeException(), isNull);
  });
}
