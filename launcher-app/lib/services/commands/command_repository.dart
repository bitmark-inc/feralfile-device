import 'dart:convert';
import '../logger.dart';
import 'screen_rotation_handler.dart';
import 'keyboard_handler.dart';

abstract class CommandHandler {
  Future<void> execute(Map<String, dynamic> data);
}

class CommandRepository {
  static final CommandRepository _instance = CommandRepository._internal();
  factory CommandRepository() => _instance;

  final Map<String, CommandHandler> _handlers = {};

  CommandRepository._internal() {
    // Register handlers
    _handlers['rotate'] = ScreenRotationHandler();
    _handlers['sendKeyboardEvent'] = KeyboardHandler();
    // Add more handlers here as needed
  }

  Future<void> executeCommand(String command, String data) async {
    try {
      final handler = _handlers[command];
      if (handler != null) {
        final Map<String, dynamic> jsonData = json.decode(data);
        await handler.execute(jsonData);
      } else {
        logger.warning('No handler found for command: $command');
      }
    } catch (e) {
      logger.warning('Error executing command $command: $e');
    }
  }
}
