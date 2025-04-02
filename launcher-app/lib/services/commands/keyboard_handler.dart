import 'dart:io';
import 'dart:convert';
import 'package:feralfile/generated/protos/command.pb.dart';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class KeyboardHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data,
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    final int keyCode = data['code'] as int;
    final String keyName = String.fromCharCode(keyCode);
    logger.info('KeyboardHandler: keyName = $keyName');

    try {
      // Use xdotool to send key events to the active window.
      final result = await Process.run('xdotool', ['key', keyName]);
      if (result.exitCode != 0) {
        logger.warning('Failed to send keyboard event: ${result.stderr}');
      } else {
        logger.info('Keyboard event sent: keyCode=$keyCode');
      }

      // Send success notification if replyId is provided.
      if (replyId != null) {
        bluetoothService.notify(replyId, CommandResponse()..success = true);
      }
    } catch (e) {
      logger.severe('Error in keyboard event: $e');
      if (replyId != null) {
        final response = CommandResponse()
          ..success = false
          ..error = e.toString();
        bluetoothService.notify(replyId, response);
      }
      rethrow;
    }
  }
}