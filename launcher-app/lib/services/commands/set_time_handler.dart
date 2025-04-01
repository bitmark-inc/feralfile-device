import 'dart:convert';
import 'package:process_run/stdio.dart';
import 'package:feralfile/generated/protos/command.pb.dart';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class SetTimezoneHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final timezone = data['timezone'] as String;
      final time = data['time'] as String?;

      try {
        // Set timezone first.
        var timezoneResult = await Process.run(
            'sudo', ['timedatectl', 'set-timezone', timezone]);
        logger.info('Set timezone result: ${timezoneResult.stdout}');

        // If time is provided, set it.
        if (time != null) {
          // Turn off NTP.
          var ntpResult =
              await Process.run('sudo', ['timedatectl', 'set-ntp', 'false']);
          logger.info('Set ntp result: ${ntpResult.stdout}');
          var timeResult =
              await Process.run('sudo', ['timedatectl', 'set-time', time]);
          logger.info('Set time result: ${timeResult.stdout}');
        }

        if (replyId != null) {
          final response = CommandResponse()
            ..success = true;
          bluetoothService.notify(replyId, response);
        }
      } catch (e) {
        logger.severe('Error setting timezone/time: $e');
        rethrow;
      }
    } catch (e) {
      logger.severe('Error setting timezone/time: $e');
      if (replyId != null) {
        final response = CommandResponse()
          ..success = false
          ..error = 'Failed to set timezone/time: ${e.toString()}';
        bluetoothService.notify(replyId, response);
      }
    }
  }
}