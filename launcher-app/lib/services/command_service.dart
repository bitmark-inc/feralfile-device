import 'dart:async';

class CommandService {
  static final CommandService _instance = CommandService._internal();
  factory CommandService() => _instance;

  final _commandController = StreamController<CommandData>.broadcast();
  Stream<CommandData> get commandStream => _commandController.stream;

  CommandService._internal();

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
