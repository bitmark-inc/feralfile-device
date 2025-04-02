import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/generated/protos/command.pb.dart';

import '../logger.dart';
import 'command_repository.dart';

class SendLogHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data,
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    logger.info('SendLogHandler data: $data');
    final userId = data['userId'];
    final title = data['title'];
    sendLog(userId, title);
  }
}
