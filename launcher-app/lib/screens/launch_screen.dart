import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:after_layout/after_layout.dart';
import '../services/commands/cursor_handler.dart';
import '../services/logger.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import '../services/commands/screen_rotation_handler.dart';
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
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize screen rotation
      logger.info('Initializing screen rotation...');
      await ScreenRotationHandler().initializeRotation();
      await CursorHandler.initializeScreenDimensions();

      // Check WiFi connection
      logger.info('Checking WiFi connection...');
      bool isConnected = await WifiService.isConnectedToWifi();

      if (!mounted) return;

      if (isConnected) {
        logger.info('WiFi connected. Launching Chromium...');
        // Launch Chromium first
        await ChromiumLauncher.launchAndWait();

        // Then navigate to home screen
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        logger.info('WiFi not connected. Showing home screen...');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      logger.severe('Error during app initialization: $e');
      // In case of error, show home screen
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
