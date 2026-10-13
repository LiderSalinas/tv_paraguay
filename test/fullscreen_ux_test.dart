import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/main.dart';
import 'package:tv_paraguay/widgets/video_panel.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player.dart';

final fixture = jsonEncode(List.generate(15, (i) => {
      'id': i + 1,
      'name': i == 0 ? 'ABC Digital' : i == 1 ? 'ESPN Latinoamérica' : 'Canal ${i + 1}',
      'shortName': i == 0 ? 'ABC' : 'TV',
      'category': 'Nacional',
      'playerType': 'hls',
      'streamUrl': 'https://example.test/${i + 1}.m3u8',
      'isActive': true,
    }));

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> openFullscreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
  await flush(tester);
  await tester.tap(find.byKey(const ValueKey('enter-fullscreen')));
  await flush(tester);
}

bool isFullscreen(WidgetTester tester) =>
    tester.widget<VideoPanel>(find.byType(VideoPanel)).isFullScreen;

void main() {
  late VideoPlayerPlatform original;
  late FakePlayer player;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    player = FakePlayer();
    VideoPlayerPlatform.instance = player;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  Future<void> app(WidgetTester tester, Future<void> Function() body) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(740, 400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(const TvParaguayApp());
      await flush(tester);
      await body();
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    }, () => MockClient((_) async => http.Response(fixture, 200)));
    expect(tester.takeException(), isNull);
  }

  testWidgets('touch opens the list and changes channel without leaving fullscreen', (tester) async {
    await app(tester, () async {
      await openFullscreen(tester);
      final current = player.sources.length;
      await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
      await flush(tester);
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsOneWidget);
      expect(player.sources.length, current);
      await tester.tap(find.byKey(const ValueKey('channel-2')));
      await flush(tester);
      expect(isFullscreen(tester), isTrue);
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsNothing);
      expect(player.sources.last, 'https://example.test/2.m3u8');
      expect(find.text('En reproducción'), findsWidgets);
    });
  });

  testWidgets('rotation, controls and fullscreen transitions retain the controller', (tester) async {
    await app(tester, () async {
      final count = player.sources.length;
      await openFullscreen(tester);
      tester.view.physicalSize = const Size(390, 844);
      await flush(tester);
      tester.view.physicalSize = const Size(1280, 720);
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
      await flush(tester);
      await tester.tapAt(const Offset(900, 350));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('exit-fullscreen')));
      await flush(tester);
      expect(isFullscreen(tester), isFalse);
      expect(player.sources.length, count);
      expect(player.disposed, isEmpty);
    });
  });

  testWidgets('remote OK selects the focused row and channel keys switch directly', (tester) async {
    await app(tester, () async {
      await openFullscreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await flush(tester);
      final before = player.sources.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await flush(tester);
      expect(player.sources.length, before);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await flush(tester);
      expect(player.sources.last, 'https://example.test/2.m3u8');
      expect(isFullscreen(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.channelUp);
      await flush(tester);
      expect(player.sources.last, 'https://example.test/3.m3u8');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await flush(tester);
      expect(player.sources.last, 'https://example.test/15.m3u8');
    });
  });

  testWidgets('Android back closes the panel before exiting fullscreen', (tester) async {
    await app(tester, () async {
      await openFullscreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await flush(tester);
      await tester.binding.handlePopRoute();
      await flush(tester);
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsNothing);
      expect(isFullscreen(tester), isTrue);
      await tester.binding.handlePopRoute();
      await flush(tester);
      expect(isFullscreen(tester), isFalse);
    });
  });

  testWidgets('back closes visible controls before exiting; remote Back has the same order', (tester) async {
    await app(tester, () async {
      await openFullscreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.goBack);
      await flush(tester);
      expect(isFullscreen(tester), isTrue);
      expect(find.byKey(const ValueKey('exit-fullscreen')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.goBack);
      await flush(tester);
      expect(isFullscreen(tester), isFalse);
    });
  });

  testWidgets('panel expires after inactivity but stays open while a finger is down', (tester) async {
    await app(tester, () async {
      await openFullscreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await flush(tester);
      await tester.pump(const Duration(seconds: 3));
      final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('channel-1'))));
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsOneWidget);
      await finger.cancel();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await flush(tester);
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsNothing);
      expect(isFullscreen(tester), isTrue);
    });
  });

  testWidgets('a pending channel does not prevent opening the fullscreen list', (tester) async {
    final delayed = Completer<http.Response>();
    tester.view.physicalSize = const Size(740, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final channels = jsonDecode(fixture) as List;
    channels.first['webUrl'] = 'https://gentv.desdepylabs.com/External/gentv';
    await http.runWithClient(() async {
      await tester.pumpWidget(const TvParaguayApp());
      await flush(tester);
      await openFullscreen(tester);
      await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
      await flush(tester);
      expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('channel-2')));
      await flush(tester);
      expect(player.sources.last, 'https://example.test/2.m3u8');
      delayed.complete(http.Response('offline', 503));
      await flush(tester);
      expect(player.sources.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
    }, () => MockClient((request) async => request.url.host == 'gentv.desdepylabs.com'
        ? delayed.future : http.Response(jsonEncode(channels), 200)));
    expect(tester.takeException(), isNull);
  });
}
