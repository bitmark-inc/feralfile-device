import 'dart:io';
import '../logger.dart';
import 'command_repository.dart';

class KeyboardHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    final int keyCode = data['code'] as int;

    try {
      // Using xdotool to send key events to the active window
      final result = await Process.run('xdotool', ['key', keyCode.toString()]);
      if (result.exitCode != 0) {
        logger.warning('Failed to send keyboard event: ${result.stderr}');
      } else {
        logger.info('Keyboard event sent: keyCode=$keyCode');
      }
    } catch (e) {
      logger.warning('Error sending keyboard event: $e');
    }
  }
}
