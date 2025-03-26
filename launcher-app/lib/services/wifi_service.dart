// lib/services/wifi_service.dart
import 'dart:async';
import 'dart:io';

import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:feralfile/services/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/wifi_credentials.dart';
import '../services/config_service.dart';

class WifiService {
  // Singleton instance
  static WifiService? _instance;
  // Singleton pattern
  factory WifiService() {
    _instance ??= WifiService._internal();
    return _instance!;
  }

  Timer? _scanningTimer;
  bool internetConnected = InternetConnectivityService().isOnline;

  WifiService._internal() {
    if (InternetConnectivityService().isOnline) {
      _stopScanning();
    } else {
      _startScanning();
    }
    // Subscribe to connectivity changes.
    InternetConnectivityService().onStatusChange.listen((status) {
      if (status && !internetConnected) {
        logger.info('Internet is online. Stopping wifi scanning.');
        internetConnected = true;
        _stopScanning();
      } else if (!status && internetConnected) {
        logger.info('Internet is offline. Starting wifi scanning.');
        internetConnected = false;
        _startScanning();
      }
    });
  }

  void _startScanning({Duration interval = const Duration(seconds: 10)}) async {
    if (_scanningTimer != null && _scanningTimer!.isActive) return;
    await Process.run(
      'nmcli',
      ['device', 'wifi', 'rescan'],
    );
    _scanningTimer = Timer.periodic(interval, (_) async {
      await Process.run(
        'nmcli',
        ['device', 'wifi', 'rescan'],
      );
    });
  }

  void _stopScanning() {
    _scanningTimer?.cancel();
    _scanningTimer = null;
  }

  // Connect to Wi-Fi using nmcli
  static Future<bool> _saveCredentials(WifiCredentials credentials) async {
    return ConfigService.updateWifiCredentials(credentials);
  }

  static Future<String?> getCurrentWifiSSID() async {
    try {
      ProcessResult scanResult = await Process.run(
        'nmcli',
        ['-t', '-f', 'SSID', 'dev', 'wifi'],
        runInShell: true,
      );
      if (scanResult.exitCode != 0) {
        throw Exception('nmcli command failed: ${scanResult.stderr}');
      }

      String ssid = scanResult.stdout.toString().trim();
      if (ssid.isNotEmpty) {
        return ssid;
      }
    } catch (e) {
      logger.info('Error getting current Wi-Fi SSID: $e');
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

      // Continue scanning until timeout or explicit stop condition
      while (DateTime.now().isBefore(endTime)) {
        var networkMap = await getAvailableSSIDs();
        await onResultScan(networkMap);

        // Check if we should stop scanning
        if (await shouldStopScan?.call(networkMap) ?? false) {
          break;
        }
        await Future.delayed(scanInterval);
      }
    } catch (e) {
      logger.info('Error scanning Wi-Fi: $e');
      Sentry.captureException('Error scanning Wi-Fi: $e');
    }
  }

  static Future<bool> connect(WifiCredentials credentials) async {
    try {
      logger.info('Delete existing credential...');
      // Delete existing connection profile
      await Process.run('nmcli', ['connection', 'delete', credentials.ssid]);
      logger.info('Attempting to connect...');
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
        logger
            .info('Connected to Wi-Fi using credentials: ${credentials.ssid}');
        await _saveCredentials(credentials);
        return true;
      } else {
        logger.info('Failed to connect with credentials: ${newConnect.stderr}');
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
