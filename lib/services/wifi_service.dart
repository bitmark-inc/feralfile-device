// lib/services/wifi_service.dart
import 'dart:io';
import 'package:feralfile/services/logger.dart';

import '../models/wifi_credentials.dart';

class WifiService {
  // Connect to Wi-Fi using nmcli
  static Future<bool> connect(WifiCredentials credentials) async {
    try {
      // First, check if the SSID is already known
      ProcessResult checkResult = await Process.run(
        'nmcli',
        ['-t', '-f', 'SSID', 'dev', 'wifi'],
      );

      if (checkResult.exitCode == 0) {
        List<String> ssids = checkResult.stdout
            .toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();

        if (!ssids.contains(credentials.ssid)) {
          // Add the new Wi-Fi connection
          ProcessResult addResult = await Process.run(
            'nmcli',
            [
              'dev',
              'wifi',
              'connect',
              credentials.ssid,
              'password',
              credentials.password,
            ],
          );

          if (addResult.exitCode == 0) {
            logger.info('Connected to Wi-Fi: ${credentials.ssid}');
            return true;
          } else {
            logger.info('Failed to connect to Wi-Fi: ${addResult.stderr}');
            return false;
          }
        } else {
          logger.info('SSID already known. Attempting to connect...');
          // Attempt to connect
          ProcessResult connectResult = await Process.run(
            'nmcli',
            ['dev', 'wifi', 'connect', credentials.ssid],
          );

          if (connectResult.exitCode == 0) {
            logger.info('Connected to Wi-Fi: ${credentials.ssid}');
            return true;
          } else {
            logger.info('Failed to connect to Wi-Fi: ${connectResult.stderr}');
            return false;
          }
        }
      } else {
        logger.info('Failed to list Wi-Fi networks: ${checkResult.stderr}');
        return false;
      }
    } catch (e) {
      logger.info('Error connecting to Wi-Fi: $e');
      return false;
    }
  }
}
