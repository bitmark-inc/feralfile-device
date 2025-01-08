import 'dart:convert';
import '../logger.dart';
import 'screen_rotation_handler.dart';
import 'keyboard_handler.dart';
import 'cursor_handler.dart';
import 'javascript_handler.dart';
import 'dart:io';

abstract class CommandHandler {
  Future<void> execute(Map<String, dynamic> data);
}

class CommandRepository {
  static final CommandRepository _instance = CommandRepository._internal();
  factory CommandRepository() => _instance;

  final Map<String, CommandHandler> _handlers = {};
  final _jsHandler = JavaScriptHandler();

  CommandRepository._internal() {
    // Register handlers for system-level commands only
    _handlers['rotate'] = ScreenRotationHandler();
    _handlers['sendKeyboardEvent'] = KeyboardHandler();
    _handlers['dragGesture'] = CursorHandler();
  }

  Future<void> executeCommand(String command, String data) async {
    try {
      final handler = _handlers[command];
      if (handler != null) {
        // Handle system-level commands with registered handlers
        final Map<String, dynamic> jsonData = json.decode(data);
        await handler.execute(jsonData);
      } else {
        // Pass through unhandled commands to Chromium via JavaScript
        await _jsHandler.execute({'command': command, 'data': data});
      }
    } catch (e) {
      logger.severe('Error executing command $command: $e');
    }
  }
}
