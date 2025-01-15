import 'dart:io';

import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';

class ChromiumLauncher {
  static Process? _chromiumProcess;
  static WebSocketService? _wsService;

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
      _chromiumProcess = await Process.start('chromium', [
        '--kiosk',
        '--disable-extensions',
        '--remote-debugging-port=9222',
        '--no-first-run',
        '--disable-translate',
        '--disable-infobars',
        '--disable-session-crashed-bubble',
        '--disable-features=TranslateUI',
        url,
      ]);

      logger.info('Chromium launched in kiosk mode.');

      _wsService!.addMessageListener((message) {
        // Handle system-level messages
        logger.info('Chromium received message: $message');
      });
    } catch (e) {
      logger.severe('Error launching Chromium: $e');
    }
  }

  static Future<void> launchAndWait() async {
    // await launchChromium('https://display.feralfile.com');
    await launchChromium(
        'https://support-feralfile-device.feralfile-display.pages.dev/');
  }

  static void dispose() {
    _chromiumProcess?.kill();
    _chromiumProcess = null;
    _wsService?.dispose();
  }
}
