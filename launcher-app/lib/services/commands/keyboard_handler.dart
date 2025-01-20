import 'dart:io';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class KeyboardHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final int keyCode = data['code'] as int;

    try {
      // Using xdotool to send key events to the active window
      final result = await Process.run('xdotool', ['key', keyCode.toString()]);
      if (result.exitCode != 0) {
        logger.warning('Failed to send keyboard event: ${result.stderr}');
      } else {
        logger.info('Keyboard event sent: keyCode=$keyCode');
      }

      // Send success notification using replyId if available
      if (replyId != null) {
        bluetoothService.notify(replyId, {'success': true});
      }
    } catch (e) {
      logger.severe('Error in keyboard event: $e');
      if (replyId != null) {
        bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
      rethrow;
    }
  }
}
