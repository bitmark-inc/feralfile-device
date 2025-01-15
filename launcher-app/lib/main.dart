// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/launch_screen.dart';
import 'cubits/ble_connection_cubit.dart';
import 'services/logger.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setFullScreen(true);

  await setupLogging();

  runApp(const FeralFileApp());
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
