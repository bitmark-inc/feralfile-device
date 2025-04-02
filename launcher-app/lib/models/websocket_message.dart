import 'dart:convert';

import 'package:feralfile/generated/protos/command.pbserver.dart';
import 'package:feralfile/models/command.dart';
import 'package:uuid/uuid.dart';

class RequestMessageData {
  final Command command;
  final Map<String, dynamic>? request;
  final String? userId;
  final String? userName;

  RequestMessageData({required this.command, this.request, this.userId, this.userName});

  factory RequestMessageData.fromJson(Map<String, dynamic> json, UserInfo? userInfo) {
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
      command: Command.fromString(json['command']),
      request: requestMap,
      userId: userInfo?.id,
      userName: userInfo?.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command.name,
        'request': request ?? {},
        'userId': userId ?? '',
        'userName': userName ?? '',
      };
}

class WebSocketRequestMessage {
  String? messageID;
  final RequestMessageData? message;

  WebSocketRequestMessage({this.messageID, this.message}) {
    messageID ??= const Uuid().v4();
  }

  factory WebSocketRequestMessage.fromJson(Map<String, dynamic> json, UserInfo? userInfo) {
    return WebSocketRequestMessage(
      messageID: json['messageID'],
      message: RequestMessageData.fromJson(json['message'], userInfo),
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
