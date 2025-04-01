import 'dart:async';
import 'dart:convert';
import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'commands/command_repository.dart';

class CommandService {
  static final CommandService _instance = CommandService._internal();
  factory CommandService() => _instance;

  final _commandController = StreamController<CommandData>.broadcast();
  CommandRepository? _commandRepository;

  Stream<CommandData> get commandStream => _commandController.stream;

  CommandService._internal() {
    _commandController.stream.listen(_processCommand);
  }

  void initialize(BluetoothService bluetoothService) {
    _commandRepository ??= CommandRepository(bluetoothService);
  }

  void _processCommand(CommandData cmdData) async {
    logger.info('Processing command: "${cmdData.command}"');
    logger.info('Command data: "${cmdData.data}"');
    if (cmdData.replyId.isNotEmpty) {
      logger.info('Reply ID: "${cmdData.replyId}"');
    }

    try {
      await _commandRepository!.executeCommand(cmdData);
      logger.info('Command processed successfully: ${cmdData.command}');
    } catch (e) {
      logger.severe('Error processing command ${cmdData.command}: $e');
      if (cmdData.replyId.isNotEmpty) {
        // Build a JSON-encoded error response.
        final response = CommandResponse()
          ..success = false
          ..message = jsonEncode({'error': e.toString()});
        _commandRepository!.bluetoothService
            .notify(cmdData.replyId, response);
      }
    }
  }

  void handleCommand(CommandData commandData) {
    logger.info('Handling new command: "${commandData.command}"');
    _commandController.add(commandData);
  }

  void dispose() {
    _commandController.close();
  }
}