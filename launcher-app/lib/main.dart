// lib/main.dart
import 'dart:io';

import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:feralfile/services/wifi_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';
import 'package:window_manager/window_manager.dart';

import 'cubits/ble_connection_cubit.dart';
import 'environment.dart';
import 'screens/launch_screen.dart';
import 'services/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setFullScreen(true);

  await setupLogging();

  await Environment.load();

  await SentryFlutter.init(
    (options) {
      options.dsn = Environment.sentryDSN;
      options.sampleRate = 0.1;
      options.addIntegration(LoggingIntegration(minEventLevel: Level.WARNING));
      options.release = Environment.appVersion;
    },
    appRunner: () async {
      // Start monitoring the internet
      InternetConnectivityService().startMonitoring();
      WifiService();

      final BLEConnectionCubit bleConnectionCubit = BLEConnectionCubit();

      // Listen for SIGTERM and cleanup
      ProcessSignal.sigterm.watch().listen((signal) async {
        logger.info('[App] Received SIGTERM: ${signal.toString()}');
        await bleConnectionCubit.close();
        HardwareMonitorService().dispose();
        logger.info('[App] Cleanup complete. Exiting...');
        exit(0);
      });

      runApp(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bleConnectionCubit),
          ],
          child: const FeralFileApp(),
        ),
      );
    },
  );
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
      home: const LaunchScreen(),
    );
  }
}
