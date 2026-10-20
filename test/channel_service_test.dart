import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/services/channel_service.dart';

const _remoteUrl = 'https://example.test/canales.json';

String _channelListJson({
  required String name,
  int id = 1,
  String playerType = 'hls',
  String streamUrl = 'https://stream.example.test/live.m3u8',
  String externalPackage = '',
  bool isActive = true,
}) {
  return jsonEncode([
    {
      'id': id,
      'name': name,
      'shortName': name,
      'category': 'Prueba',
      'playerType': playerType,
      'streamUrl': streamUrl,
      'webUrl': '',
      'logoUrl': '',
      'externalPackage': externalPackage,
      'httpHeaders': <String, String>{},
      'isActive': isActive,
    },
  ]);
}

class _MemoryChannelListCache implements ChannelListCache {
  String? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String jsonString) async {
    value = jsonString;
  }
}

void main() {
  group('ChannelService', () {
    test(
      'prioriza Internet, evita caché HTTP y guarda una copia válida',
      () async {
        final cache = _MemoryChannelListCache();
        late http.Request capturedRequest;
        final remoteJson = _channelListJson(name: 'REMOTO');
        final client = MockClient((request) async {
          capturedRequest = request;
          return http.Response(remoteJson, 200);
        });
        final service = ChannelService(
          httpClient: client,
          cache: cache,
          assetLoader: () async => _channelListJson(name: 'ASSET'),
          remoteUrls: const [_remoteUrl],
          clock: () => DateTime.utc(2026, 9, 3),
        );

        final result = await service.getChannels();

        expect(result.source, ChannelListSource.remote);
        expect(result.channels.single.name, 'REMOTO');
        expect(cache.value, remoteJson);
        expect(capturedRequest.url.queryParameters['_refresh'], isNotEmpty);
        expect(capturedRequest.headers['Cache-Control'], contains('no-cache'));
        expect(capturedRequest.headers['Pragma'], 'no-cache');
        service.dispose();
      },
    );

    test(
      'recibe una lista modificada al reabrir sin cambiar el binario',
      () async {
        final cache = _MemoryChannelListCache();
        final firstService = ChannelService(
          httpClient: MockClient(
            (_) async =>
                http.Response(_channelListJson(name: 'VERSIÓN A'), 200),
          ),
          cache: cache,
          assetLoader: () async => _channelListJson(name: 'ASSET'),
          remoteUrls: const [_remoteUrl],
        );

        final firstResult = await firstService.getChannels();
        firstService.dispose();

        final reopenedService = ChannelService(
          httpClient: MockClient(
            (_) async =>
                http.Response(_channelListJson(name: 'VERSIÓN B'), 200),
          ),
          cache: cache,
          assetLoader: () async => _channelListJson(name: 'ASSET'),
          remoteUrls: const [_remoteUrl],
        );

        final reopenedResult = await reopenedService.getChannels();

        expect(firstResult.channels.single.name, 'VERSIÓN A');
        expect(reopenedResult.source, ChannelListSource.remote);
        expect(reopenedResult.channels.single.name, 'VERSIÓN B');
        expect(cache.value, contains('VERSIÓN B'));
        reopenedService.dispose();
      },
    );

    test('sin Internet usa la última lista remota válida guardada', () async {
      final cache =
          _MemoryChannelListCache()
            ..value = _channelListJson(name: 'ÚLTIMA VÁLIDA');
      final service = ChannelService(
        httpClient: MockClient((_) async => http.Response('sin conexión', 503)),
        cache: cache,
        assetLoader: () async => throw StateError('No debe leer el asset'),
        remoteUrls: const [_remoteUrl],
      );

      final result = await service.getChannels();

      expect(result.source, ChannelListSource.cached);
      expect(result.channels.single.name, 'ÚLTIMA VÁLIDA');
      service.dispose();
    });

    test(
      'usa el asset solo si nunca hubo una descarga remota válida',
      () async {
        final service = ChannelService(
          httpClient: MockClient(
            (_) async => http.Response('sin conexión', 503),
          ),
          cache: _MemoryChannelListCache(),
          assetLoader: () async => _channelListJson(name: 'RESPALDO APK'),
          remoteUrls: const [_remoteUrl],
        );

        final result = await service.getChannels();

        expect(result.source, ChannelListSource.bundled);
        expect(result.channels.single.name, 'RESPALDO APK');
        service.dispose();
      },
    );

    test('una respuesta inválida no reemplaza la copia válida', () async {
      final cache =
          _MemoryChannelListCache()
            ..value = _channelListJson(name: 'COPIA SEGURA');
      final service = ChannelService(
        httpClient: MockClient(
          (_) async => http.Response('<html></html>', 200),
        ),
        cache: cache,
        assetLoader: () async => _channelListJson(name: 'ASSET'),
        remoteUrls: const [_remoteUrl],
      );

      final result = await service.getChannels();

      expect(result.source, ChannelListSource.cached);
      expect(result.channels.single.name, 'COPIA SEGURA');
      expect(cache.value, contains('COPIA SEGURA'));
      service.dispose();
    });

    test('descarta canales activos que no sean HLS directos', () async {
      final json = jsonEncode([
        jsonDecode(_channelListJson(name: 'HLS'))[0],
        jsonDecode(
          _channelListJson(
            name: 'WEB',
            id: 2,
            playerType: 'webview',
            streamUrl: 'https://example.test/ver-en-vivo',
          ),
        )[0],
      ]);
      final service = ChannelService(
        httpClient: MockClient((_) async => http.Response(json, 200)),
        cache: _MemoryChannelListCache(),
        assetLoader: () async => _channelListJson(name: 'ASSET'),
        remoteUrls: const [_remoteUrl],
      );

      final result = await service.getChannels();

      expect(result.channels, hasLength(1));
      expect(result.channels.single.name, 'HLS');
      service.dispose();
    });

    test('acepta un acceso nativo a una aplicación oficial', () async {
      final externalJson = _channelListJson(
        name: 'ESPN — DISNEY+',
        playerType: 'externalApp',
        streamUrl: '',
        externalPackage: 'com.disney.disneyplus',
      );
      final service = ChannelService(
        httpClient: MockClient((_) async => http.Response(externalJson, 200)),
        cache: _MemoryChannelListCache(),
        assetLoader: () async => _channelListJson(name: 'ASSET'),
        remoteUrls: const [_remoteUrl],
      );

      final result = await service.getChannels();

      expect(result.channels, hasLength(1));
      expect(result.channels.single.isExternalApp, isTrue);
      expect(
        result.channels.single.externalPackage,
        'com.disney.disneyplus',
      );
      service.dispose();
    });

    test('rechaza un acceso externo sin paquete Android', () async {
      final invalidExternalJson = _channelListJson(
        name: 'EXTERNO INVÁLIDO',
        playerType: 'externalApp',
        streamUrl: '',
      );
      final service = ChannelService(
        httpClient: MockClient(
          (_) async => http.Response(invalidExternalJson, 200),
        ),
        cache: _MemoryChannelListCache(),
        assetLoader: () async => _channelListJson(name: 'RESPALDO'),
        remoteUrls: const [_remoteUrl],
      );

      final result = await service.getChannels();

      expect(result.source, ChannelListSource.bundled);
      expect(result.channels.single.name, 'RESPALDO');
      service.dispose();
    });
  });
}
