// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  final BLEConnectionCubit bleConnectionCubit = BLEConnectionCubit()
    ..startListening();

  // Listen for SIGTERM and cleanup
  ProcessSignal.sigterm.watch().listen((signal) async {
    logger.info('[App] Received SIGTERM: ${signal.toString()}');
    await bleConnectionCubit.close();
    HardwareMonitorService().dispose();
    logger.info('[App] Cleanup complete. Exiting...');
    exit(0);
  });

  runZonedGuarded(() {
    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bleConnectionCubit),
        ],
        child: const FeralFileApp(),
      ),
    );
  }, (error, stackTrace) {
    logger.info('Uncaught error: $error\n$stackTrace');
  });
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
