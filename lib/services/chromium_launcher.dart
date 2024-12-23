import 'dart:io';

import 'package:feralfile/services/logger.dart';

class ChromiumLauncher {
  // Launch Chromium in full-screen mode with the specified URL
  static Future<void> launchChromium(String url) async {
    try {
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
    } catch (e) {
      logger.info('Error launching Chromium: $e');
    }
  }
}
