import 'dart:convert';
import 'package:feralfile/models/app_config.dart';
import 'package:feralfile/models/command.dart';
import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/config_service.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:feralfile/generated/protos/command.pb.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class JavaScriptHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data,
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    try {
      final requestMessageData = RequestMessageData.fromJson(data, userInfo);
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
            // Wrap the response message (which is assumed to be JSON or JSON-compatible)
            // inside a CommandResponse protobuf message.
            final cmdResp = CommandResponse()
              ..success = true
              ..message = response.message;
            bluetoothService.notify(replyId, cmdResp);
            
            // Process art framing updates if applicable.
            if (requestMessageData.command == Command.updateArtFraming) {
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
              logger.info('Updated art framing to: ${artFraming.name}');
            }
          },
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${data['command']}: $e');
    }
  }
}