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
    final String keyName = String.fromCharCode(keyCode);
    logger.info('keyname', keyName);

    try {
      // Map character to xdotool key name
      final String xdoKey = _mapToXdoKey(keyCode, keyName);

      // Using xdotool to send key events to the active window
      final result = await Process.run('xdotool', ['key', xdoKey]);
      if (result.exitCode != 0) {
        logger.warning('Failed to send keyboard event: ${result.stderr}');
      } else {
        logger.info('Keyboard event sent: keyCode=$keyCode, xdoKey=$xdoKey');
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

  // Maps character codes to valid xdotool key names
  String _mapToXdoKey(int keyCode, String keyName) {
    // Common special characters that need mapping
    switch (keyCode) {
      case 32: // Space
        return 'space';
      case 9: // Tab
        return 'Tab';
      case 13: // Enter/Return
        return 'Return';
      case 27: // Escape
        return 'Escape';
      case 8: // Backspace
        return 'BackSpace';
      default:
        // For regular alphanumeric characters
        return keyName;
    }
  }
}
