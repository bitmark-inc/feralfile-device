import 'package:feralfile/cubits/ble_connection_cubit.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:after_layout/after_layout.dart';
import '../services/commands/cursor_handler.dart';
import '../services/logger.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import '../services/commands/screen_rotation_handler.dart';
import 'home_screen.dart';
import '../services/config_service.dart';
import '../cubits/ble_connection_state.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with AfterLayoutMixin<LaunchScreen> {
  @override
  void afterFirstLayout(BuildContext context) {
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize screen rotation
      logger.info('Initializing screen rotation...');
      await ScreenRotationHandler().initializeRotation();
      await CursorHandler.initializeScreenDimensions();

      // Initialize Bluetooth service
      final bleConnectionCubit = context.read<BLEConnectionCubit>();
      await bleConnectionCubit.initialize();

      // Check WiFi connection
      logger.info('Checking WiFi connection...');
      bool isConnected = await WifiService.isConnectedToWifi();

      if (!mounted) return;

      // Start log server & WebSocket server if connected to WiFi
      if (isConnected) {
        logger.info('Starting log server...');
        await startLogServer();
        logger.info('Starting WebSocket server...');
        await WebSocketService().initServer();
      }

      // Navigate to home screen
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    } catch (e) {
      logger.severe('Error during app initialization: $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = size.width / 4; // 1/4 of screen width

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/ff-logo.svg',
              width: logoSize,
              height: logoSize,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
