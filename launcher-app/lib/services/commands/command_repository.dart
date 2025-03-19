import 'dart:convert';

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
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]);
}

class CommandRepository {
  static CommandRepository? _instance;
  factory CommandRepository(BluetoothService bluetoothService) {
    _instance ??= CommandRepository._internal(bluetoothService);
    return _instance!;
  }

  final Map<String, CommandHandler> _handlers = {};
  final _jsHandler = JavaScriptHandler();
  final BluetoothService _bluetoothService;

  CommandRepository._internal(this._bluetoothService) {
    // Register handlers for system-level commands only
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

  Future<void> executeCommand(String command, String data,
      [String? replyId]) async {
    try {
      final handler = _handlers[command];
      if (handler != null) {
        // Handle system-level commands with registered handlers
        final Map<String, dynamic> jsonData = json.decode(data);
        await handler.execute(jsonData, _bluetoothService, replyId);
      } else {
        // Pass through unhandled commands to Chromium via JavaScript
        await _jsHandler.execute(
          {
            'command': command,
            'request': data,
          },
          _bluetoothService,
          replyId,
        );
      }
    } catch (e) {
      logger.severe('Error executing command $command: $e');
      // If we have a replyId, send an error notification
      if (replyId != null) {
        _bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
    }
  }
}
