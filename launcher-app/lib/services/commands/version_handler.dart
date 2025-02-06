import 'package:feralfile/environment.dart';
import 'package:feralfile/services/bluetooth_service.dart';

import '../logger.dart';
import 'command_repository.dart';

class VersionHandler implements CommandHandler {
  String _loadVersion() {
    return Environment.appVersion;
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final version = _loadVersion();
    if (replyId == null) {
      logger.warning('No replyId provided for version command');
      return;
    }
    bluetoothService.notify(replyId, {'version': version});
  }
}
