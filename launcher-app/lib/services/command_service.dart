import 'dart:async';

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
    await _commandRepository.executeCommand(cmdData.command, cmdData.data);
  }

  void handleCommand(String command, String data) {
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
