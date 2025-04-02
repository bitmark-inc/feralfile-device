import 'dart:convert';

import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/services/commands/device_info_handler.dart';
import 'package:feralfile/services/commands/metrics_streaming_handlers.dart';
import 'package:feralfile/services/commands/scan_wifi_handler.dart';
import 'package:feralfile/services/commands/send_log_handler.dart';
import 'package:feralfile/services/commands/version_handler.dart';
import 'package:feralfile/services/commands/version_update_handler.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'cursor_handler.dart';
import 'javascript_handler.dart';
import 'keyboard_handler.dart';
import 'screen_rotation_handler.dart';
import 'set_time_handler.dart';

abstract class CommandHandler {
  Future<void> execute(Map<String, dynamic> data,
      BluetoothService bluetoothService, 
      [String? replyId, UserInfo? userInfo]);
}

class CommandRepository {
  static CommandRepository? _instance;
  factory CommandRepository(BluetoothService bluetoothService) {
    _instance ??= CommandRepository._internal(bluetoothService);
    return _instance!;
  }

  final Map<String, CommandHandler> _handlers = {};
  final _jsHandler = JavaScriptHandler();
  final BluetoothService bluetoothService;

  CommandRepository._internal(this.bluetoothService) {
    // Register handlers.
    _handlers['rotate'] = ScreenRotationHandler();
    _handlers['sendKeyboardEvent'] = KeyboardHandler();
    _handlers['dragGesture'] = CursorHandler();
    _handlers['tapGesture'] = CursorHandler();
    _handlers['sendLog'] = SendLogHandler();
    _handlers['getVersion'] = VersionHandler();
    _handlers['getBluetoothDeviceStatus'] = DeviceStatusHandler();
    _handlers['setTimezone'] = SetTimezoneHandler();
    _handlers['updateToLatestVersion'] = VersionUpdateHandler();
    _handlers['scanWifi'] = ScanWifiHandler();
    _handlers['enableMetricsStreaming'] = EnableMetricsStreamingHandler();
    _handlers['disableMetricsStreaming'] = DisableMetricsStreamingHandler();
  }

  Future<void> executeCommand(CommandData commandData) async {
    try {
      final handler = _handlers[commandData.command];
      if (handler != null) {
        // Decode JSON from the command's data field.
        final Map<String, dynamic> jsonData = json.decode(commandData.data);
        await handler.execute(
          jsonData,
          bluetoothService,
          commandData.replyId.isNotEmpty ? commandData.replyId : null,
        );
      } else {
        await _jsHandler.execute(
          {
            'command': commandData.command,
            'request': commandData.data,
          },
          bluetoothService,
          commandData.replyId.isNotEmpty ? commandData.replyId : null,
          commandData.userInfo,
        );
      }
    } catch (e) {
      logger.severe('Error executing command ${commandData.command}: $e');
      if (commandData.replyId.isNotEmpty) {
        final response = CommandResponse()
          ..success = false
          ..error = e.toString();
        bluetoothService.notify(
            commandData.replyId, response);
      }
    }
  }
}