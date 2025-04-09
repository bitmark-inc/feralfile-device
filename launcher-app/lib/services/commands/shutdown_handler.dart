import 'dart:async';
import 'dart:io';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/commands/command_repository.dart';

class ShutdownHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    ProcessResult shutdownResult = await Process.run(
      'sudo',
      ['shutdown', '-h', 'now'],
      runInShell: true,
    );

    if (shutdownResult.exitCode != 0) {
      throw Exception('shutdown command failed: ${shutdownResult.stderr}');
    }
    if (replyId != null) {
      bluetoothService.notify(replyId, {'success': true});
    }
  }
}
