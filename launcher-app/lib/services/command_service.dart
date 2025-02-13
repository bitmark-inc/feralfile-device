import 'dart:async';

import 'package:feralfile/services/logger.dart';

import 'commands/command_repository.dart';
import 'bluetooth_service.dart';

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
    if (cmdData.replyId != null) {
      logger.info('Reply ID: "${cmdData.replyId}"');
    }

    try {
      await _commandRepository!
          .executeCommand(cmdData.command, cmdData.data, cmdData.replyId);
      logger.info('Command processed successfully: ${cmdData.command}');
    } catch (e) {
      logger.severe('Error processing command ${cmdData.command}: $e');
    }
  }

  void handleCommand(String command, String data, [String? replyId]) {
    logger.info('Handling new command: "$command"');
    _commandController.add(CommandData(command, data, replyId));
  }

  void dispose() {
    _commandController.close();
  }
}

class CommandData {
  final String command;
  final String data;
  final String? replyId;

  CommandData(this.command, this.data, [this.replyId]);
}
