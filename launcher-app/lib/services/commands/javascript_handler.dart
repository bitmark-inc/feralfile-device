import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/websocket_service.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class JavaScriptHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final requestMessageData = RequestMessageData.fromJson(data);
      if (replyId == null) {
        WebSocketService().sendMessage(
          WebSocketRequestMessage(
            message: requestMessageData,
          ),
        );
      } else {
        WebSocketService().sendMessageWithCallback(
          WebSocketRequestMessage(
            messageID: replyId,
            message: requestMessageData,
          ),
          (response) {
            bluetoothService.notify(replyId, response.message);
            logger.info('Received response: $response');
          },
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}
