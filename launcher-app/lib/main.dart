// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/home_screen.dart';
import 'cubits/ble_connection_cubit.dart';
import 'services/logger.dart';
import 'services/wifi_service.dart';
import 'services/chromium_launcher.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setFullScreen(true);

  setupLogging();

  // Check if already connected to WiFi
  // bool isConnected = await WifiService.isConnectedToWifi();
  bool isConnected = false;
  if (isConnected) {
    logger.info('Already connected to WiFi. Launching Chromium directly...');
    await ChromiumLauncher.launchAndWait();
  } else {
    logger.info('No WiFi connection. Starting connection UI...');
    runApp(const FeralFileApp());
  }
}

class FeralFileApp extends StatelessWidget {
  const FeralFileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feral File',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: BlocProvider(
        create: (context) => BLEConnectionCubit()..startListening(),
        child: const HomeScreen(),
      ),
    );
  }
}
