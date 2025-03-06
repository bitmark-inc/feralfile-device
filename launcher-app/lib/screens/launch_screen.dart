import 'package:after_layout/after_layout.dart';
import 'package:feralfile/cubits/ble_connection_cubit.dart';
import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:feralfile/services/rotate_service.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:feralfile/utils/version_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/commands/cursor_handler.dart';
import '../services/config_service.dart';
import '../services/logger.dart';
import '../services/wifi_service.dart';
import 'home_screen.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with AfterLayoutMixin<LaunchScreen> {
  @override
  void afterFirstLayout(BuildContext context) {
    // Allow the frame to complete rendering
    Future.delayed(const Duration(milliseconds: 100), () {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize screen rotation
      logger.info('Initializing screen rotation...');
      await RotateService.initializeRotation();
      await CursorHandler.initializeScreenDimensions();

      // Initialize Bluetooth service
      final bleConnectionCubit = context.read<BLEConnectionCubit>();
      await bleConnectionCubit.initialize();

      // Check WiFi connection
      logger.info('Checking WiFi connection...');
      bool isConnected = await WifiService.isConnectedToWifi();

      if (!isConnected) {
        logger.info('Not connected to WiFi. Checking stored credentials...');
        final config = await ConfigService.loadConfig();

        if (config?.wifiCredentials != null) {
          logger.info('Found stored credentials. Attempting to connect...');
          isConnected = await WifiService.connect(config!.wifiCredentials!);
        } else {
          logger.info('No stored WiFi credentials found.');
        }
      }

      if (!mounted) return;

      // Start log server & WebSocket server if connected to WiFi
      if (isConnected) {
        logger.info('Starting log server...');
        await startLogServer();
        logger.info('Starting WebSocket server...');
        await WebSocketService().initServer();

        logger.info('Starting hardware monitoring...');
        HardwareMonitorService().startMonitoring();
        _updateToLatestVersion();
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

  Future<void> _updateToLatestVersion() async {
    // Update to latest version
    logger.info('Updating to latest version...');
    try {
      await VersionHelper.updateToLatestVersion();
    } catch (e) {
      logger.severe('Error updating to latest version: $e');
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
