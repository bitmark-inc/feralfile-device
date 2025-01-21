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
            logger.info('Received response: $response');
            logger.info('Sending response to Bluetooth: ${response.message}');
            bluetoothService.notify(replyId, response.message);
          },
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}
