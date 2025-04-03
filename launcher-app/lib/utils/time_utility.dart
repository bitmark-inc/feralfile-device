import 'dart:io';
import 'package:feralfile/services/logger.dart';

class TimeUtility {
  static Future<void> enableNTP() async {
    var ntpResult =
        await Process.run('sudo', ['timedatectl', 'set-ntp', 'true']);
    logger.info('Enable NTP result: ${ntpResult.stdout}');
  }

  static Future<void> disableNTP() async {
    var ntpResult =
        await Process.run('sudo', ['timedatectl', 'set-ntp', 'false']);
    logger.info('Disable NTP result: ${ntpResult.stdout}');
  }

  static Future<void> setTimezone(String timezone) async {
    var result =
        await Process.run('sudo', ['timedatectl', 'set-timezone', timezone]);
    logger.info('Set timezone result: ${result.stdout}');
  }

  static Future<void> setTime(String time, bool hasInternet) async {
    if (hasInternet) {
      // If internet is available, just ensure NTP is enabled
      await enableNTP();
    } else {
      // If no internet, disable NTP and set time manually
      await disableNTP();
      var timeResult =
          await Process.run('sudo', ['timedatectl', 'set-time', time]);
      logger.info('Set time result: ${timeResult.stdout}');
    }
  }
}
