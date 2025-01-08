import 'dart:io';

import 'package:feralfile/services/logger.dart';

class ChromiumLauncher {
  static Process? _chromiumProcess;

  static Future<void> launchChromium(String url) async {
    try {
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
        url,
        '--no-first-run',
        '--disable-translate',
        '--disable-infobars',
        '--disable-session-crashed-bubble',
        '--disable-features=TranslateUI',
      ]);

      logger.info('Chromium launched in kiosk mode.');
    } catch (e) {
      logger.severe('Error launching Chromium: $e');
    }
  }

  static Future<void> launchAndWait() async {
    await launchChromium('https://display.feralfile.com');
  }

  static void dispose() {
    _chromiumProcess?.kill();
    _chromiumProcess = null;
  }
}
