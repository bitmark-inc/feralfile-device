import 'package:feralfile/utils/time_utility.dart';
import 'package:process_run/stdio.dart';

import '../bluetooth_service.dart';
import '../internet_connectivity_service.dart';
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
        bool hasInternet =
            await InternetConnectivityService().checkConnectivity();

        if (hasInternet) {
          await TimeUtility.enableNTP();
          await TimeUtility.setTimezone(timezone);
        } else {
          // Set up one-time listener for next internet connection
          InternetConnectivityService()
              .onStatusChange
              .firstWhere((status) => status)
              .then((_) async {
            logger.info(
                'Internet connection restored. Setting timezone and enabling NTP.');
            await TimeUtility.enableNTP();
            await TimeUtility.setTimezone(timezone);
          });
          logger.info(
              'No internet connection. Will set timezone on next connection.');
        }

        // Handle time setting if provided
        if (time != null) {
          await TimeUtility.setTime(time, hasInternet);
        }

        if (replyId != null) {
          bluetoothService.notify(replyId, {'success': true});
        }
      } catch (e) {
        logger.severe('Error setting timezone/time: $e');
        rethrow;
      }
    } catch (e) {
      logger.severe('Error setting timezone/time: $e');
      if (replyId != null) {
        bluetoothService.notify(replyId, {
          'success': false,
          'error': 'Failed to set timezone/time: ${e.toString()}'
        });
      }
    }
  }
}
