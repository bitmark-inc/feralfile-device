import 'dart:convert';

import 'package:feralfile/models/command.dart';
import 'package:uuid/uuid.dart';

class RequestMessageData {
  final Command command;
  final String? request;

  RequestMessageData({required this.command, this.request});

  factory RequestMessageData.fromJson(Map<String, dynamic> json) {
    return RequestMessageData(
      command: Command.fromString(json['command']),
      request: json['request'],
    );
  }

  Map<String, String> toJson() => {
        'command': command.name,
        'request': request ?? '',
      };
}

class WebSocketRequestMessage {
  String? messageID;
  final RequestMessageData? message;

  WebSocketRequestMessage({this.messageID, this.message}) {
    messageID ??= const Uuid().v4();
  }

  factory WebSocketRequestMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketRequestMessage(
      messageID: json['messageID'],
      message: RequestMessageData.fromJson(json['message']),
    );
  }

  Map<String, String> toJson() => {
        'messageID': messageID ?? '',
        'message': jsonEncode(message?.toJson() ?? {}),
      };
}

class WebSocketResponseMessage {
  final String? messageID;
  final dynamic message;

  WebSocketResponseMessage({this.messageID, this.message});

  factory WebSocketResponseMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketResponseMessage(
      messageID: json['messageID'],
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageID': messageID,
      'message': message,
    };
  }
}
