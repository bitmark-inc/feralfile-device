import 'package:dbus/dbus.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class SetTimeHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final timeString = data['time'] as String;
      final dateTime = DateTime.parse(timeString);

      final client = DBusClient.system();
      try {
        final microseconds = dateTime.microsecondsSinceEpoch;
        final timestamp = DBusInt64(microseconds * 1000);
        const relative = DBusBoolean(false);
        final path = DBusObjectPath('/org/freedesktop/timedate1');

        await client.callMethod(
          destination: 'org.freedesktop.timedate1',
          path: path,
          interface: 'org.freedesktop.timedate1',
          name: 'SetTime',
          values: [timestamp, relative],
        );

        if (replyId != null) {
          bluetoothService.notify(replyId, {'success': true});
        }
      } finally {
        await client.close();
      }
    } catch (e) {
      logger.severe('Error setting system time: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to set system time: ${e.toString()}'
        });
      }
    }
  }
}

class SetTimezoneHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final timezone = data['timezone'] as String;
      final path = DBusObjectPath('/org/freedesktop/timedate1');

      final client = DBusClient.system();
      try {
        await client.callMethod(
          destination: 'org.freedesktop.timedate1',
          path: path,
          interface: 'org.freedesktop.timedate1',
          name: 'SetTimezone',
          values: [DBusString(timezone)],
        );

        if (replyId != null) {
          bluetoothService.notify(replyId, {'success': true});
        }
      } finally {
        await client.close();
      }
    } catch (e) {
      logger.severe('Error setting timezone: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to set timezone: ${e.toString()}'
        });
      }
    }
  }
}
