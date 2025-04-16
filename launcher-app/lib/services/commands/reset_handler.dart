import 'dart:io';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/logger.dart';
import 'command_repository.dart';

class ResetHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final String resetType = data['type'] as String;

      switch (resetType) {
        case 'soft':
          // Execute soft reset script
          await Process.run('sudo', ['/opt/feralfile/scripts/soft-reset.sh']);
          break;
        case 'factory':
          // Execute factory reset script
          await Process.run(
              'sudo', ['/opt/feralfile/scripts/factory-reset.sh']);
          break;
        default:
          throw Exception('Invalid reset type: $resetType');
      }

      if (replyId != null) {
        bluetoothService.notify(replyId, {'success': true});
      }
    } catch (e) {
      logger.severe('Error performing reset: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to perform reset: ${e.toString()}'
        });
      }
      rethrow;
    }
  }
}
