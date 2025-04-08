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
    final ssids = await getAvailableSSIDs();
    for (final ssid in ssids.entries) {
      if (ssid.value) {
        return ssid.key;
      }
    }
    return null;
  }

  static Future<Map<String, bool>> getAvailableSSIDs({int? topN}) async {
    try {
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'SSID,ACTIVE,SIGNAL', 'dev', 'wifi'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        throw Exception('nmcli command failed: ${result.stderr}');
      }

      final Map<String, Map<String, dynamic>> deduplicatedNetworks =
          _parseAndDeduplicate(result.stdout.toString());
      final List<MapEntry<String, Map<String, dynamic>>> topNetworks =
          _selectTopNetworks(deduplicatedNetworks, topN: topN);

      return {
        for (final entry in topNetworks)
          entry.key: entry.value['active'] as bool,
      };
    } catch (e) {
      print('Error fetching Wi-Fi networks: $e');
      return {};
    }
  }

  static Map<String, Map<String, dynamic>> _parseAndDeduplicate(String stdout) {
    final lines = stdout.split('\n');
    final Map<String, Map<String, dynamic>> ssidMap = {};

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final parts = line.split(':');
      if (parts.length < 3) continue;

      final ssid = parts[0].trim();
      final isActive = parts[1].trim() == 'yes';
      final signal = int.tryParse(parts[2].trim());

      if (ssid.isEmpty || signal == null) continue;

      final existing = ssidMap[ssid];

      if (existing == null) {
        ssidMap[ssid] = {'active': isActive, 'signal': signal};
      } else if (isActive &&
          (!existing['active'] || signal > existing['signal'])) {
        ssidMap[ssid] = {'active': true, 'signal': signal};
      } else if (!existing['active'] && signal > existing['signal']) {
        ssidMap[ssid] = {'active': false, 'signal': signal};
      }
    }

    return ssidMap;
  }

  static List<MapEntry<String, Map<String, dynamic>>> _selectTopNetworks(
      Map<String, Map<String, dynamic>> ssidMap,
      {int? topN}) {
    if (topN == null || topN <= 0) {
      return ssidMap.entries.toList();
    }
    // Find the strongest connected SSID (if any)
    final connectedEntries =
        ssidMap.entries.where((e) => e.value['active'] == true);
    final strongestConnected = connectedEntries.isEmpty
        ? null
        : connectedEntries.reduce((a, b) =>
            (a.value['signal'] as int) >= (b.value['signal'] as int) ? a : b);

    // Sort unconnected by signal, exclude the connected one
    final unconnectedEntries = ssidMap.entries
        .where((e) =>
            e.value['active'] == false &&
            (strongestConnected == null || e.key != strongestConnected.key))
        .toList()
      ..sort((a, b) =>
          (b.value['signal'] as int).compareTo(a.value['signal'] as int));

    // Compose the final result: connected first (if any), then top N others
    final topList = <MapEntry<String, Map<String, dynamic>>>[
      if (strongestConnected != null) strongestConnected,
      ...unconnectedEntries.take(strongestConnected != null ? topN - 1 : topN),
    ];

    return topList;
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
        var networkMap = await getAvailableSSIDs(topN: 10);
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
