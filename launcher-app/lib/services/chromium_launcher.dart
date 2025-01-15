import 'dart:io';

import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';

class ChromiumLauncher {
  static WebSocketService? _wsService;

  // Launch Chromium in full-screen mode with the specified URL
  static Future<void> launchChromium(String url) async {
    try {
      // Init WebSocket server
      _wsService = WebSocketService();
      await _wsService?.initServer();

      // Check if Chromium is installed
      ProcessResult whichResult = await Process.run('which', ['chromium']);
      if (whichResult.exitCode != 0) {
        logger.info('Chromium is not installed.');
        return;
      }

      // Launch Chromium in kiosk mode (full-screen without UI elements)
      await Process.start('chromium', [
        '--kiosk',
        '--disable-extensions',
        url,
        '--no-first-run',
        '--disable-translate',
        '--disable-infobars',
        '--disable-session-crashed-bubble',
        '--disable-features=TranslateUI',
      ]);

      logger.info('Chromium launched in kiosk mode.');

      _wsService!.addMessageListener((message) {
        // Handle system-level messages
        logger.info('Chromium received message: $message');
      });
    } catch (e) {
      logger.info('Error launching Chromium: $e');
    }
  }

  static Future<void> launchAndExit() async {
    await launchChromium(
        'https://support-feralfile-device.feralfile-display.pages.dev/');
    exit(0);
  }

  static void dispose() {
    _wsService?.dispose();
  }
}
