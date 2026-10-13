import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/models/channel.dart';
import 'package:tv_paraguay/widgets/video_panel.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakePlayer extends VideoPlayerPlatform {
  final sources = <String>[];
  final disposed = <int>[];
  final played = <int>[];
  final paused = <int>[];

  @override
  Future<void> init() async {}
  @override
  Future<int> create(DataSource dataSource) async {
    sources.add(dataSource.uri!);
    return sources.length;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(hours: 1),
      size: const Size(1280, 720),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    paused.add(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool isLooping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 1);
  @override
  Widget buildView(int playerId) => const SizedBox();
}

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
    'automatic failures stop after two retries; manual retry resets the budget',
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
}
