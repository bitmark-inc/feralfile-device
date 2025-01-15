import 'dart:async';

import 'package:feralfile/services/logger.dart';

import 'commands/command_repository.dart';

class CommandService {
  static final CommandService _instance = CommandService._internal();
  factory CommandService() => _instance;

  final _commandController = StreamController<CommandData>.broadcast();
  final _commandRepository = CommandRepository();

  Stream<CommandData> get commandStream => _commandController.stream;

  CommandService._internal() {
    _commandController.stream.listen(_processCommand);
  }

  void _processCommand(CommandData cmdData) async {
    logger.info('Processing command: "${cmdData.command}"');
    logger.info('Command data: "${cmdData.data}"');

    try {
      await _commandRepository.executeCommand(cmdData.command, cmdData.data);
      logger.info('Command processed successfully: ${cmdData.command}');
    } catch (e) {
      logger.severe('Error processing command ${cmdData.command}: $e');
    }
  }

  void handleCommand(String command, String data) {
    logger.info('Handling new command: "$command"');
    _commandController.add(CommandData(command, data));
  }

  void dispose() {
    _commandController.close();
  }
}

class CommandData {
  final String command;
  final String data;

  CommandData(this.command, this.data);
}
