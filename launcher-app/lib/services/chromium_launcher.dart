import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:feralfile/services/logger.dart';

class ChromiumLauncher {
  static Browser? _browser;
  static Page? _page;

  static Future<void> launchChromium(String url) async {
    try {
      // Check if Chromium is installed
      ProcessResult whichResult = await Process.run('which', ['chromium']);
      if (whichResult.exitCode != 0) {
        logger.info('Chromium is not installed.');
        return;
      }

      // Launch browser
      _browser = await puppeteer.launch(
        headless: false,
        args: [
          '--kiosk',
          '--disable-extensions',
          '--disable-translate',
          '--disable-infobars',
          '--disable-session-crashed-bubble',
          '--disable-features=TranslateUI',
        ],
        executablePath: whichResult.stdout.toString().trim(),
      );

      if (_browser == null) {
        logger.severe('Failed to launch Chromium');
        return;
      }

      // Create new page and navigate
      _page = await _browser!.newPage();
      await _page!.goto(url);

      logger.info('Chromium launched in kiosk mode.');
    } catch (e) {
      logger.severe('Error launching Chromium: $e');
    }
  }

  static Future<String?> evaluateJavaScript(String expression) async {
    try {
      if (_page == null) {
        logger.warning('No active page to evaluate JavaScript');
        return null;
      }

      final result = await _page?.evaluate(expression);
      return result?.toString();
    } catch (e) {
      logger.severe('Error evaluating JavaScript: $e');
      return null;
    }
  }

  static Future<void> launchAndWait() async {
    await launchChromium('https://display.feralfile.com');
  }

  static void dispose() {
    _browser?.close();
    _browser = null;
    _page = null;
  }
}
