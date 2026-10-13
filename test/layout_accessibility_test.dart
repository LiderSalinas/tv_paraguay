import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/screens/home_screen.dart';
import 'package:tv_paraguay/theme/app_theme.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player.dart';

void main() {
  final fixture = jsonEncode([
    {'id': 16, 'name': 'ABC Digital', 'shortName': 'ABC', 'streamUrl': 'https://example.test/abc.m3u8'},
    {'id': 24, 'name': 'ESPN Latinoamérica', 'shortName': 'ESPN', 'streamUrl': 'https://example.test/espn.m3u8'},
    {'id': 22, 'name': 'FIFA+ Latinoamérica', 'shortName': 'FIFA', 'streamUrl': 'https://example.test/fifa.m3u8'},
    {'id': 20, 'name': 'Oasis TV Misiones', 'shortName': 'Oasis', 'streamUrl': 'https://example.test/oasis.m3u8'},
  ]);
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = FakePlayer();
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  for (final size in [const Size(320, 568), const Size(390, 844), const Size(740, 360), const Size(1280, 720)]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('layout ${size.width}x${size.height} at text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
        await font.load();
        final boundary = GlobalKey();
        await http.runWithClient(() async {
          await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: buildAppTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const HomeScreen(),
            ),
          ));
          for (var i = 0; i < 10; i++) { await tester.pump(); }
          expect(tester.takeException(), isNull);
          if (scale == 1 && (size.width == 390 || size.width == 1280)) {
            await capture(tester, boundary, size.width == 390 ? 'movil' : 'tvbox');
          }
          await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('enter-fullscreen')));
          for (var i = 0; i < 5; i++) { await tester.pump(); }
          await tester.tap(find.byKey(const ValueKey('video-touch-surface')));
          for (var i = 0; i < 5; i++) { await tester.pump(); }
          expect(find.byKey(const ValueKey('fullscreen-channel-panel')), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (scale == 1 && size.width == 1280) {
            await capture(tester, boundary, 'pantalla-completa');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 5; i++) { await tester.pump(); }
        }, () => MockClient((_) async => http.Response.bytes(utf8.encode(fixture), 200)));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pump();
  final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('build/ux-previews')..createSync(recursive: true);
    File('${directory.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
