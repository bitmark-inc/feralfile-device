import 'dart:convert';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'screen_rotation_handler.dart';
import 'keyboard_handler.dart';
import 'cursor_handler.dart';
import 'javascript_handler.dart';

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
        await _jsHandler.execute({
          'command': command,
          'request': data,
          'messageID':
              replyId, // Pass replyId as messageID for JavaScript handling
        }, _bluetoothService);
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
