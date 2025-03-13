// lib/services/wifi_service.dart
import 'dart:async';
import 'dart:io';

import 'package:feralfile/services/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';

import '../models/wifi_credentials.dart';
import '../services/config_service.dart';

class WifiService {
  // Connect to Wi-Fi using nmcli
  static Future<bool> _saveCredentials(WifiCredentials credentials) async {
    return ConfigService.updateWifiCredentials(credentials);
  }

  static Future<String?> getCurrentWifiSSID() async {
    final ssids = await getAvailableSSIDs();
    for (final ssid in ssids.entries) {
      if (ssid.value) {
        return ssid.key;
      }
    }
    return null;
  }

  static Future<Map<String, bool>> getAvailableSSIDs() async {
    try {
      ProcessResult scanResult = await Process.run(
        'nmcli',
        ['-t', '-f', 'SSID,ACTIVE', 'dev', 'wifi'],
        runInShell: true,
      );

      if (scanResult.exitCode != 0) {
        throw Exception('nmcli command failed: ${scanResult.stderr}');
      }

      Map<String, bool> wifiNetworks = {};

      for (String line in scanResult.stdout.toString().split('\n')) {
        if (line.trim().isEmpty) continue;

        List<String> parts = line.split(':');
        if (parts.length < 2) continue;

        String ssid = parts[0].trim();
        bool isActive = parts[1].trim() == "yes";

        wifiNetworks[ssid] = isActive;
      }

      return wifiNetworks;
    } catch (e) {
      print('Error fetching Wi-Fi networks: $e');
      return {};
    }
  }

  static Future<void> _rescanWifi() async {
    await Process.run(
      'nmcli',
      ['device', 'wifi', 'rescan'],
    );
  }

  static Future<void> scanWifiNetwork(
      {required Duration timeout,
      required FutureOr<void> Function(Map<String, bool>) onResultScan,
      FutureOr<bool> Function(Map<String, bool>)? shouldStopScan}) async {
    try {
      // Scan current wifi and sleep for 3s first
      _rescanWifi();

      // Retry mechanism to allow Wi-Fi scan to update, up to timeout duration
      final delay = Duration(seconds: 2);
      final startTime = DateTime.now();
      bool stopScan = false;
      while (DateTime.now().difference(startTime) < timeout && !stopScan) {
        await Future.delayed(delay);

        final availableSSIDs = await getAvailableSSIDs();

        _rescanWifi();
        await onResultScan(availableSSIDs);
        stopScan = await shouldStopScan?.call(availableSSIDs) ?? false;
      }
    } catch (e) {
      logger.info('Error scanning Wi-Fi: $e');
      Sentry.captureException('Error scanning Wi-Fi: $e');
    }
  }

  static Future<bool> connect(WifiCredentials credentials) async {
    try {
      bool isSSIDAvailable = false;
      await scanWifiNetwork(
          timeout: Duration(seconds: 15),
          onResultScan: (result) {
            final ssids = result.keys;
            if (ssids.contains(credentials.ssid)) {
              isSSIDAvailable = true;
            }
          },
          shouldStopScan: (result) {
            final ssids = result.keys;
            return !ssids.contains(credentials.ssid);
          });

      if (!isSSIDAvailable) {
        logger.info('SSID not found: ${credentials.ssid}');
        return false;
      }

      logger.info('SSID found.');

      if (InternetConnectivityService().isOnline) {
        logger.info('Internet already connected.');
        return true;
      }

      logger.info('Attempting to connect...');
      logger.info('Delete existing credential...');

      // Delete existing connection profile
      await Process.run('nmcli', ['connection', 'delete', credentials.ssid]);

      // Attempt to connect with new credentials
      ProcessResult newConnect = await Process.run(
        'nmcli',
        [
          'dev',
          'wifi',
          'connect',
          credentials.ssid,
          'password',
          credentials.password
        ],
        runInShell: true,
      );
      if (newConnect.exitCode == 0) {
        logger.info(
            'Connected to Wi-Fi using credentials: ${credentials.ssid}');
        await _saveCredentials(credentials);
        return true;
      } else {
        logger.info(
            'Failed to connect with credentials: ${newConnect.stderr}');
        return false;
      }
    } catch (e) {
      logger.info('Error connecting to Wi-Fi: $e');
      return false;
    }
  }

  // Check internet connection by pinging multiple DNS servers
  static Future<bool> checkInternetConnection() async {
    final List<String> dnsServers = ['8.8.8.8', '1.1.1.1', '9.9.9.9'];

    for (final server in dnsServers) {
      try {
        ProcessResult pingResult = await Process.run(
          'ping',
          ['-c', '1', '-W', '1', server],
        );

        if (pingResult.exitCode == 0) {
          logger.info(
              'Internet connection is available (ping to $server successful)');
          return true;
        }
      } catch (e) {
        logger.info('Ping to $server failed: $e');
      }
    }

    logger.info('No internet access (all ping attempts failed)');
    return false;
  }

  static Future<bool> isConnectedToWifi() async {
    try {
      ProcessResult result = await Process.run(
        'nmcli',
        ['-t', '-f', 'DEVICE,STATE', 'dev'],
      );

      if (result.exitCode == 0) {
        List<String> connections = result.stdout.toString().trim().split('\n');
        logger.info('[Check internet] Connections: $connections');
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
