import 'package:process_run/stdio.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class SetTimezoneHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final timezone = data['timezone'] as String;
      try {
        var result = await Process.run(
            'sudo', ['timedatectl', 'set-timezone', timezone]);
        logger.info('Set timezone result: ${result.stdout}');
        if (replyId != null) {
          bluetoothService.notify(replyId, {'success': true});
        }
      } catch (e) {
        logger.severe('Error setting timezone: $e');
        rethrow;
      }
    } catch (e) {
      logger.severe('Error setting timezone: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to set timezone: ${e.toString()}'
        });
      }
    }
  }
}
