// lib/services/wifi_service.dart
import 'dart:io';
import 'package:feralfile/services/logger.dart';

import '../models/wifi_credentials.dart';
import '../services/config_service.dart';

class WifiService {
  // Connect to Wi-Fi using nmcli
  static Future<bool> _saveCredentials(WifiCredentials credentials) async {
    return ConfigService.updateWifiCredentials(credentials);
  }

  static Future<bool> connect(WifiCredentials credentials) async {
    try {
      // Scan current wifi and sleep for 3s first
      await Process.run(
        'nmcli',
        ['device', 'wifi', 'rescan'],
      );

      // Retry mechanism to allow Wi-Fi scan to update, up to 10s
      List<String> availableSSIDs = [];
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration(seconds: 2));

        ProcessResult scanResult = await Process.run(
          'nmcli',
          ['-t', '-f', 'SSID', 'device', 'wifi', 'list'],
          runInShell: true,
        );

        availableSSIDs = scanResult.stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (availableSSIDs.contains(credentials.ssid)) {
          break;
        }

        if (i == 4) {
          logger.info('SSID not found after multiple retries.');
          return false;
        }
      }

      logger.info('SSID found, attempting to connect...');

      // First, attempt to connect using existing credentials if existed
      ProcessResult initialConnect = await Process.run(
        'nmcli',
        ['dev', 'wifi', 'connect', credentials.ssid],
        runInShell: true,
      );
      if (initialConnect.exitCode == 0) {
        logger.info('Connected to Wi-Fi using existing credentials: ${credentials.ssid}');
        return true;
      }

      logger.info('Failed to connect with existing credentials, trying new ones...');

      // Delete existing connection profile if the first attempt fails
      await Process.run('nmcli', ['connection', 'delete', credentials.ssid]);

      // Attempt to connect with new credentials
      ProcessResult newConnect = await Process.run(
        'nmcli',
        ['dev', 'wifi', 'connect', credentials.ssid, 'password', credentials.password],
        runInShell: true,
      );
      if (newConnect.exitCode == 0) {
        logger.info('Connected to Wi-Fi using new credentials: ${credentials.ssid}');
        await _saveCredentials(credentials);
        return true;
      } else {
        logger.info('Failed to connect with new credentials: ${newConnect.stderr}');
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

  static Future<String> getLocalIpAddress() async {
    try {
      final result = await Process.run('hostname', ['-I']);
      if (result.exitCode == 0) {
        final ips = result.stdout.toString().trim().split(' ');
        if (ips.isNotEmpty) {
          return ips.first;
        }
      }
      return 'localhost';
    } catch (e) {
      logger.warning('Error getting local IP: $e');
      return 'localhost';
    }
  }
}
