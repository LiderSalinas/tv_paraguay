import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/channel_service.dart';
import 'services/external_app_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TvParaguayApp());
}

class TvParaguayApp extends StatelessWidget {
  const TvParaguayApp({
    super.key,
    this.channelService,
    this.externalAppLauncher,
  });

  final ChannelService? channelService;
  final ExternalAppLauncher? externalAppLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV Paraguay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        channelService: channelService,
        externalAppLauncher: externalAppLauncher,
      ),
    );
  }
}
