import 'package:flutter/services.dart';

enum ExternalAppLaunchResult { opened, storeOpened, unavailable }

abstract interface class ExternalAppLauncher {
  Future<ExternalAppLaunchResult> launch(String packageName);
}

class PlatformExternalAppLauncher implements ExternalAppLauncher {
  static const MethodChannel _channel = MethodChannel(
    'tv_paraguay/external_apps',
  );

  @override
  Future<ExternalAppLaunchResult> launch(String packageName) async {
    final result = await _channel.invokeMethod<String>(
      'launch',
      {'packageName': packageName},
    );

    return switch (result) {
      'opened' => ExternalAppLaunchResult.opened,
      'storeOpened' => ExternalAppLaunchResult.storeOpened,
      _ => ExternalAppLaunchResult.unavailable,
    };
  }
}
