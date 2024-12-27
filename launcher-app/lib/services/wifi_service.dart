// lib/services/wifi_service.dart
import 'dart:io';
import 'package:feralfile/services/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../models/wifi_credentials.dart';

class WifiService {
  // Connect to Wi-Fi using nmcli
  static Future<bool> _saveCredentials(WifiCredentials credentials) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final file = File('${appDir.path}/wifi_credentials.json');
      await file.writeAsString(credentials.toJson());
      logger.info('Saved Wi-Fi credentials to file: ${file.path}');
      return true;
    } catch (e) {
      logger.warning('Failed to save Wi-Fi credentials: $e');
      return false;
    }
  }

  static Future<bool> connect(WifiCredentials credentials) async {
    try {
      // First, try to delete any existing connection with this SSID
      await Process.run(
        'nmcli',
        ['connection', 'delete', credentials.ssid],
      );

      // Add the new Wi-Fi connection with provided credentials
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
        runInShell: true,
      );

      if (addResult.exitCode == 0) {
        logger.info('Connected to Wi-Fi: ${credentials.ssid}');
        await _saveCredentials(credentials);
        return true;
      } else {
        logger.info('Failed to connect to Wi-Fi: ${addResult.stderr}');
        return false;
      }
    } catch (e) {
      logger.info('Error connecting to Wi-Fi: $e');
      return false;
    }
  }

  static Future<bool> isConnectedToWifi() async {
    try {
      ProcessResult result = await Process.run(
        'nmcli',
        ['-t', '-f', 'DEVICE,STATE', 'dev'],
      );

      if (result.exitCode == 0) {
        List<String> connections = result.stdout.toString().trim().split('\n');
        for (String connection in connections) {
          // Specifically look for the wlan0 interface
          if (connection.contains('wlan0:connected')) {
            logger.info('WiFi interface (wlan0) is connected');
            return true;
          }
        }
      }
      logger.info('WiFi interface (wlan0) is not connected');
      return false;
    } catch (e) {
      logger.warning('Error checking WiFi status: $e');
      return false;
    }
  }
}
