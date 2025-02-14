import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/utils/version_helper.dart';

import '../logger.dart';
import 'command_repository.dart';

class VersionUpdateHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      await VersionHelper.updateToLatestVersion();
      if (replyId == null) {
        logger.warning('No replyId provided for version command');
        return;
      } else {
        bluetoothService.notify(replyId, {'ok': true});
      }
    } catch (e) {
      logger.severe('Error updating to latest version: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'ok': false,
          'error': 'Failed to update to latest version: ${e.toString()}'
        });
      }
    }
  }
}
