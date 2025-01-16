import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/websocket_service.dart';

import '../logger.dart';
import 'command_repository.dart';

class JavaScriptHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    try {
      final requestMessageData = RequestMessageData.fromJson(data);
      final messageID = requestMessageData.messageID;
      if (messageID == null) {
        WebSocketService().sendMessage(
          WebSocketRequestMessage(
            message: requestMessageData,
          ),
        );
      } else {
        WebSocketService().sendMessageWithCallback(
          WebSocketRequestMessage(
            messageID: messageID,
            message: requestMessageData,
          ),
          (response) {
            logger.info('Received response: $response');
          },
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}
