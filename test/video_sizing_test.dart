import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_paraguay/models/channel.dart';
import 'package:tv_paraguay/widgets/video_panel.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player.dart';

class SizedFakePlayer extends FakePlayer {
  SizedFakePlayer(this.videoSize);

  final Size videoSize;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(hours: 1),
        size: videoSize,
      ));

  @override
  Widget buildView(int playerId) => ColoredBox(
        key: ValueKey('test-video-$playerId'),
        color: const Color(0xFF2F80ED),
      );
}

final _channel = Channel.fromJson({
  'id': 9,
  'name': 'Ñandutí TV',
  'streamUrl': 'https://example.test/nanduti.m3u8',
});

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Widget _screen({bool fullscreen = true}) => MaterialApp(
      home: VideoPanel(
        key: const ValueKey('sizing-player'),
        channel: _channel,
        isFullScreen: fullscreen,
        controlsVisible: false,
      ),
    );

void _expectPictureBounds(WidgetTester tester, Rect expected) {
  final render = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('test-video-1')),
  );
  // Measure the painted picture after transforms, not its intrinsic dimensions.
  final rect = MatrixUtils.transformRect(
    render.getTransformTo(null),
    Offset.zero & render.size,
  );
  expect(rect.left, closeTo(expected.left, 0.01));
  expect(rect.top, closeTo(expected.top, 0.01));
  expect(rect.width, closeTo(expected.width, 0.01));
  expect(rect.height, closeTo(expected.height, 0.01));
}

void main() {
  late VideoPlayerPlatform original;
  setUp(() => original = VideoPlayerPlatform.instance);
  tearDown(() => VideoPlayerPlatform.instance = original);

  Future<void> open(
    WidgetTester tester,
    Size videoSize,
    Size viewport,
    Future<void> Function(SizedFakePlayer) verify,
  ) async {
    final fake = SizedFakePlayer(videoSize);
    VideoPlayerPlatform.instance = fake;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_screen());
    await _flush(tester);
    expect(fake.sources, ['https://example.test/nanduti.m3u8']);
    await verify(fake);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);
  }

  for (final viewport in [
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(960, 540),
  ]) {
    testWidgets('360p fills the 16:9 viewport $viewport', (tester) async {
      await open(tester, const Size(640, 360), viewport, (_) async {
        _expectPictureBounds(tester, Offset.zero & viewport);
      });
    });
  }

  testWidgets('1080p fits a small mobile player without cropping', (tester) async {
    await open(tester, const Size(1920, 1080), const Size(320, 180), (_) async {
      _expectPictureBounds(tester, const Rect.fromLTWH(0, 0, 320, 180));
    });
  });

  testWidgets('4:3 video keeps its proportions and remains centered', (tester) async {
    await open(tester, const Size(640, 480), const Size(1280, 720), (_) async {
      _expectPictureBounds(tester, const Rect.fromLTWH(160, 0, 960, 720));
    });
  });

  testWidgets('portrait video stays complete without stretching', (tester) async {
    await open(tester, const Size(360, 640), const Size(1280, 720), (_) async {
      _expectPictureBounds(tester, const Rect.fromLTWH(437.5, 0, 405, 720));
    });
  });

  testWidgets('resizing and fullscreen reuse the low-resolution controller', (tester) async {
    await open(tester, const Size(640, 360), const Size(1280, 720), (fake) async {
      for (final viewport in [const Size(1920, 1080), const Size(960, 540)]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(_screen(fullscreen: false));
        await _flush(tester);
        _expectPictureBounds(tester, Offset.zero & viewport);
        expect(fake.sources, ['https://example.test/nanduti.m3u8']);
        expect(fake.disposed, isEmpty);
      }
    });
  });
}
