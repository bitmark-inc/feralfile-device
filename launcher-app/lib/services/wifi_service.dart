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

  static Future<void> scanWifiNetwork({
    required Duration timeout,
    required FutureOr<void> Function(Map<String, bool>) onResultScan,
    FutureOr<bool> Function(Map<String, bool>)? shouldStopScan,
  }) async {
    try {
      const scanInterval = Duration(seconds: 3);
      final endTime = DateTime.now().add(timeout);
      
      // Initial scan
      var networkMap = await getAvailableSSIDs();
      await onResultScan(networkMap);
      
      // Check if we should terminate after the initial scan
      if (await shouldStopScan?.call(networkMap) ?? false) {
        return;
      }
      
      // Continue scanning until timeout or explicit stop condition
      while (DateTime.now().isBefore(endTime)) {
        await Future.delayed(scanInterval);
        
        networkMap = await getAvailableSSIDs();
        await onResultScan(networkMap);
        
        // Check if we should stop scanning
        if (await shouldStopScan?.call(networkMap) ?? false) {
          break;
        }
      }
    } catch (e) {
      logger.info('Error scanning Wi-Fi: $e');
      Sentry.captureException('Error scanning Wi-Fi: $e');
    }
  }

  static Future<bool> connect(WifiCredentials credentials, int timeoutSeconds) async {
    try {
      bool isSSIDAvailable = false;
      await scanWifiNetwork(
          timeout: Duration(seconds: timeoutSeconds),
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
