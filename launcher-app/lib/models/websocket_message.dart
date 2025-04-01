import 'dart:convert';
import 'package:uuid/uuid.dart';

class RequestMessageData {
  final String command;
  final Map<String, dynamic>? request;

  RequestMessageData({required this.command, this.request});

  factory RequestMessageData.fromJson(Map<String, dynamic> json) {
    var requestData = json['request'];
    Map<String, dynamic>? requestMap;
    if (requestData is String) {
      try {
        requestMap = jsonDecode(requestData);
      } catch (e) {
        requestMap = {};
      }
    } else if (requestData is Map<String, dynamic>) {
      requestMap = requestData;
    }
    return RequestMessageData(
      command: json['command'] ?? '',
      request: requestMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'request': request ?? {},
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
