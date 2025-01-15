import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/websocket_service.dart';

import '../logger.dart';
import 'command_repository.dart';

class JavaScriptHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    try {
      final requestMessageData = RequestMessageData.fromJson(data);
      WebSocketService().sendMessage(
        WebSocketRequestMessage(
          message: requestMessageData,
        ),
      );
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}
