import 'package:feralfile/models/app_config.dart';
import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/config_service.dart';
import 'package:feralfile/services/websocket_service.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

const String updateArtFramingCommand = 'updateArtFraming';
const String pingCommand = 'ping';

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
            if (requestMessageData.command == updateArtFramingCommand) {
              logger.info(
                  'Received art framing update: ${requestMessageData.request?.keys}, ${requestMessageData.request?.values}');
              final artFramingRaw = requestMessageData.request?['frameConfig'];
              logger.info('Received art framing: $artFramingRaw');
              if (artFramingRaw == null) {
                logger.severe('Invalid art framing value: $artFramingRaw');
                return;
              }
              final artFraming = ArtFraming.fromValue(artFramingRaw);
              ConfigService.updateArtFraming(artFraming);
              logger.severe('Updated art framing to: ${artFraming.name}');
            }
          },
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}
