import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/main.dart';
import 'package:tv_paraguay/services/channel_service.dart';
import 'package:tv_paraguay/services/external_app_service.dart';

class _MemoryCache implements ChannelListCache {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String jsonString) async => value = jsonString;
}

class _FakeExternalAppLauncher implements ExternalAppLauncher {
  final List<String> launchedPackages = [];

  @override
  Future<ExternalAppLaunchResult> launch(String packageName) async {
    launchedPackages.add(packageName);
    return ExternalAppLaunchResult.opened;
  }
}

void main() {
  testWidgets('TV Paraguay inicia correctamente', (WidgetTester tester) async {
    final json = jsonEncode([
      {
        'id': 2,
        'name': 'TELEFUTURO',
        'shortName': 'TF',
        'category': 'Nacional',
        'playerType': 'hls',
        'streamUrl': 'https://example.test/telefuturo.m3u8',
        'webUrl': '',
        'logoUrl': '',
        'httpHeaders': <String, String>{},
        'isActive': true,
      },
    ]);
    final service = ChannelService(
      httpClient: MockClient((_) async => http.Response(json, 200)),
      cache: _MemoryCache(),
      assetLoader: () async => json,
      remoteUrls: const ['https://example.test/canales.json'],
    );

    await tester.pumpWidget(TvParaguayApp(channelService: service));
    await tester.pump();

    expect(find.text('TV Paraguay'), findsOneWidget);
    expect(find.text('TELEFUTURO'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('ESPN abre la aplicación oficial Disney+', (
    WidgetTester tester,
  ) async {
    final json = jsonEncode([
      {
        'id': 24,
        'name': 'ESPN — DISNEY+',
        'shortName': 'ESPN',
        'category': 'Deportes',
        'playerType': 'externalApp',
        'streamUrl': '',
        'webUrl': '',
        'logoUrl': '',
        'externalPackage': 'com.disney.disneyplus',
        'httpHeaders': <String, String>{},
        'isActive': true,
      },
    ]);
    final launcher = _FakeExternalAppLauncher();
    final service = ChannelService(
      httpClient: MockClient((_) async => http.Response(json, 200)),
      cache: _MemoryCache(),
      assetLoader: () async => json,
      remoteUrls: const ['https://example.test/canales.json'],
    );

    await tester.pumpWidget(
      TvParaguayApp(
        channelService: service,
        externalAppLauncher: launcher,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Abrir ESPN en Disney+'), findsOneWidget);
    await tester.tap(find.text('Abrir ESPN en Disney+'));
    await tester.pump();

    expect(launcher.launchedPackages, ['com.disney.disneyplus']);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}
