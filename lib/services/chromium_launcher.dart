import 'dart:io';

class ChromiumLauncher {
  // Launch Chromium in full-screen mode with the specified URL
  static Future<void> launchChromium(String url) async {
    try {
      // Check if Chromium is installed
      ProcessResult whichResult = await Process.run('which', ['chromium']);
      if (whichResult.exitCode != 0) {
        print('Chromium is not installed.');
        return;
      }

      // Launch Chromium in kiosk mode (full-screen without UI elements)
      await Process.start('chromium', [
        '--kiosk',
        url,
        '--no-first-run',
        '--disable-translate',
        '--disable-infobars',
        '--disable-session-crashed-bubble',
        '--disable-features=TranslateUI',
      ]);

      print('Chromium launched in kiosk mode.');
    } catch (e) {
      print('Error launching Chromium: $e');
    }
  }
}
