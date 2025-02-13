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
  Future<Map<String, dynamic>> _verifyTimezone(
      DBusClient client, String expectedTimezone) async {
    try {
      final path = DBusObjectPath('/org/freedesktop/timedate1');
      final result = await client.callMethod(
        destination: 'org.freedesktop.timedate1',
        path: path,
        interface: 'org.freedesktop.DBus.Properties',
        name: 'Get',
        values: [
          const DBusString('org.freedesktop.timedate1'),
          const DBusString('Timezone'),
        ],
      );

      final currentTimezone =
          (result.values.first as DBusVariant).value.asString();
      final now = DateTime.now();
      final offset = now.timeZoneOffset.inHours;
      final currentOffset = offset >= 0 ? '+$offset' : '$offset';

      return {
        'success': currentTimezone == expectedTimezone,
        'current_timezone': currentTimezone,
        'expected_timezone': expectedTimezone,
        'offset': currentOffset,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to verify timezone: ${e.toString()}'
      };
    }
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      final timezone = 'Asia/Ho_Chi_Minh'; //data['timezone'] as String;
      final path = DBusObjectPath('/org/freedesktop/timedate1');

      final client = DBusClient.system();
      try {
        await client.callMethod(
          destination: 'org.freedesktop.timedate1',
          path: path,
          interface: 'org.freedesktop.timedate1',
          name: 'SetTimezone',
          values: <DBusValue>[
            DBusString(timezone),
            const DBusBoolean(false),
          ],
        );

        try {
          logger.info('Verifying timezone');
          final result = await _verifyTimezone(client, timezone);
          logger.info('Timezone verification result: $result');
        } catch (e) {
          logger.severe('Error verifying timezone: $e');
        }

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
