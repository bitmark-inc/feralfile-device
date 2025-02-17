import 'package:feralfile/services/bluetooth_service.dart';

import '../logger.dart';
import 'command_repository.dart';

class SendLogHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('SendLogHandler data: $data');
    final userId = data['userId'];
    final title = data['title'];
    sendLog(userId, title);
  }
}
