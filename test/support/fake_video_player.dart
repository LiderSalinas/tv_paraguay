import 'package:flutter/widgets.dart';
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

