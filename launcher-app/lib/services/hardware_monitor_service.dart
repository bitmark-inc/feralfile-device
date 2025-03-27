import 'dart:async';
import 'dart:io';

import 'package:feralfile/environment.dart';
import 'package:feralfile/generated/protos/system_metrics.pb.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/metric_service.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:fixnum/src/int64.dart';

class _CachedMetrics {
  double cpuUsage = 0;
  double ramUsage = 0;
  double gpuUsage = 0;
  double cpuTemp = 0;
  double gpuTemp = 0;
  ScreenInfo screenInfo = ScreenInfo(width: 0, height: 0, connected: false);
  int uptime = 0;
  DateTime lastUpdated = DateTime.now();

  bool get isStale => DateTime.now().difference(lastUpdated).inSeconds > 30;
}

class HardwareMonitorService {
  static final HardwareMonitorService _instance =
      HardwareMonitorService._internal();
  Timer? _monitorTimer;
  Timer? _streamingTimer;
  static const _monitorInterval = Duration(minutes: 1);
  static const _streamingInterval = Duration(seconds: 5);
  bool internetConnected = InternetConnectivityService().isOnline;
  bool _hasReportedSpecs = false;
  bool _isStreamingEnabled = false;
  final BluetoothService _bluetoothService = BluetoothService();
  final _cachedMetrics = _CachedMetrics();
  final _screenRefreshInterval =
      Duration(minutes: 5); // Screen info changes rarely
  DateTime _lastScreenRefresh = DateTime.now();

  factory HardwareMonitorService() => _instance;

  HardwareMonitorService._internal() {
    // Subscribe to connectivity changes.
    InternetConnectivityService().onStatusChange.listen((status) {
      if (status && !internetConnected) {
        logger.info('Internet is online. Monitoring hardware.');
        internetConnected = true;
      } else if (!status && internetConnected) {
        logger.info('Internet is offline. Pausing hardware monitoring.');
        internetConnected = false;
      }
    });
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _reportHardwareSpecs();
    _monitorTimer = Timer.periodic(_monitorInterval, (_) {
      if (internetConnected) {
        _checkHardwareUsage();
      }
    });
    logger.info(
        'Hardware monitoring started with ${_monitorInterval.inMinutes} minute interval');
  }

  void startMetricsStreaming() {
    if (_isStreamingEnabled) return;

    _isStreamingEnabled = true;
    _streamingTimer?.cancel();
    _streamingTimer =
        Timer.periodic(_streamingInterval, (_) => _streamHardwareMetrics());

    logger.info(
        'Hardware metrics streaming started with ${_streamingInterval.inSeconds} second interval');
  }

  void stopMetricsStreaming() {
    _streamingTimer?.cancel();
    _streamingTimer = null;
    _isStreamingEnabled = false;
    logger.info('Hardware metrics streaming stopped');
  }

  Future<void> _streamHardwareMetrics() async {
    try {
      await _collectMetricsBatch();

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create and populate the protobuf message
      final metrics = DeviceRealtimeMetrics()
        ..cpuUsage = _cachedMetrics.cpuUsage
        ..memoryUsage = _cachedMetrics.ramUsage
        ..gpuUsage = _cachedMetrics.gpuUsage
        ..cpuTemperature = _cachedMetrics.cpuTemp
        ..gpuTemperature = _cachedMetrics.gpuTemp
        ..screenWidth = _cachedMetrics.screenInfo.width.toInt()
        ..screenHeight = _cachedMetrics.screenInfo.height.toInt()
        ..uptimeSeconds = Int64(_cachedMetrics.uptime)
        ..timestamp = Int64(timestamp);

      // Serialize to binary format
      final bytes = metrics.writeToBuffer();

      // Send via Bluetooth engineering characteristic
      _bluetoothService.sendEngineeringData(bytes);

      logger.info(
          'Streamed hardware metrics - CPU: ${_cachedMetrics.cpuUsage.toStringAsFixed(2)}%, '
          'RAM: ${_cachedMetrics.ramUsage.toStringAsFixed(2)}%, '
          'GPU Clock: ${_cachedMetrics.gpuUsage.toStringAsFixed(2)}MHz, '
          'CPU Temp: ${_cachedMetrics.cpuTemp.toStringAsFixed(1)}°C, '
          'GPU Temp: ${_cachedMetrics.gpuTemp.toStringAsFixed(1)}°C, '
          'Resolution: ${_cachedMetrics.screenInfo.width.toInt()}x${_cachedMetrics.screenInfo.height.toInt()}, '
          'Uptime: ${Duration(seconds: _cachedMetrics.uptime).toString()}, '
          'Timestamp: ${DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String()}');
    } catch (e) {
      logger.severe('Error streaming hardware metrics: $e');
    }
  }

  Future<void> _collectMetricsBatch() async {
    if (!_cachedMetrics.isStale) {
      _cachedMetrics.uptime = await _getSystemUptime();
      return;
    }

    final futures = await Future.wait([
      _getCPUUsageFromProc(),
      _getRAMUsage(),
      _getGPUMetrics(),
      _getCPUTemperature(),
      _getSystemUptime(),
    ]);

    _cachedMetrics.cpuUsage = futures[0] as double;
    _cachedMetrics.ramUsage = futures[1] as double;
    final gpuMetrics = futures[2] as Map<String, double>;
    _cachedMetrics.gpuUsage = gpuMetrics['usage'] ?? 0;
    _cachedMetrics.gpuTemp = gpuMetrics['temp'] ?? 0;
    _cachedMetrics.cpuTemp = futures[3] as double;
    _cachedMetrics.uptime = futures[4] as int;

    final now = DateTime.now();
    if (now.difference(_lastScreenRefresh) >= _screenRefreshInterval) {
      _cachedMetrics.screenInfo = await _getScreenInfo();
      _lastScreenRefresh = now;
    }

    _cachedMetrics.lastUpdated = now;
  }

  Future<Map<String, double>> _getGPUMetrics() async {
    final result = <String, double>{'usage': 0, 'temp': 0};

    try {
      final commands =
          ['vcgencmd measure_clock v3d', 'vcgencmd measure_temp'].join(' && ');

      final procResult = await Process.run('sh', ['-c', commands]);

      if (procResult.exitCode == 0) {
        final output = procResult.stdout.toString().split('\n');

        if (output.length > 0) {
          final clockMatch = RegExp(r'=(\d+)').firstMatch(output[0]);
          if (clockMatch != null) {
            final clockSpeedHz = double.parse(clockMatch.group(1)!);
            result['usage'] = clockSpeedHz / 1000000.0;
          }
        }

        if (output.length > 1) {
          final tempMatch = RegExp(r'temp=(\d+\.\d+)').firstMatch(output[1]);
          if (tempMatch != null) {
            result['temp'] = double.parse(tempMatch.group(1)!);
          }
        }
      }
    } catch (e) {
      logger.warning('Error getting GPU metrics: $e');
    }

    return result;
  }

  Future<void> _checkHardwareUsage() async {
    try {
      // Collect all system metrics in one go
      final systemMetrics = await _collectSystemMetrics();

      logger.info(
          'Hardware usage - CPU: ${systemMetrics['cpuUsage'].toStringAsFixed(2)}%, '
          'RAM: ${systemMetrics['ramUsage'].toStringAsFixed(2)}%, '
          'GPU Clock: ${systemMetrics['gpuUsage'].toStringAsFixed(2)}MHz, '
          'CPU Temp: ${systemMetrics['cpuTemp'].toStringAsFixed(1)}°C, '
          'GPU Temp: ${systemMetrics['gpuTemp'].toStringAsFixed(1)}°C');

      // Send metrics - removed Chromium status
      MetricService().sendEvent(
        'hardware_usage',
        doubleData: [
          systemMetrics['cpuUsage'],
          systemMetrics['ramUsage'],
          systemMetrics['gpuUsage'],
          systemMetrics['cpuTemp'],
          systemMetrics['gpuTemp'],
          systemMetrics['uptime'].toDouble(),
        ],
      );
    } catch (e) {
      logger.severe('Error checking hardware usage: $e');
    }
  }

  Future<double> _getCPUUsageFromProc() async {
    try {
      final file = File('/proc/stat');
      final statBefore = await file.readAsString();
      final beforeValues = _parseCPUStats(statBefore);

      // Small delay for comparison
      await Future.delayed(Duration(milliseconds: 500));

      final statAfter = await file.readAsString();
      final afterValues = _parseCPUStats(statAfter);

      return _calculateCPUPercentage(beforeValues, afterValues);
    } catch (e) {
      logger.warning('Error getting CPU usage from /proc/stat: $e');
      return 0.0;
    }
  }

  Map<String, int> _parseCPUStats(String stat) {
    final lines = stat.split('\n');
    for (final line in lines) {
      if (line.startsWith('cpu ')) {
        final parts =
            line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 8) {
          return {
            'user': int.parse(parts[1]),
            'nice': int.parse(parts[2]),
            'system': int.parse(parts[3]),
            'idle': int.parse(parts[4]),
            'iowait': int.parse(parts[5]),
            'irq': int.parse(parts[6]),
            'softirq': int.parse(parts[7]),
          };
        }
      }
    }
    return {
      'user': 0,
      'nice': 0,
      'system': 0,
      'idle': 0,
      'iowait': 0,
      'irq': 0,
      'softirq': 0
    };
  }

  double _calculateCPUPercentage(
      Map<String, int> before, Map<String, int> after) {
    final idleDelta = after['idle']! - before['idle']!;
    final totalDelta = (after['user']! - before['user']!) +
        (after['nice']! - before['nice']!) +
        (after['system']! - before['system']!) +
        idleDelta +
        (after['iowait']! - before['iowait']!) +
        (after['irq']! - before['irq']!) +
        (after['softirq']! - before['softirq']!);

    if (totalDelta == 0) return 0.0;
    return 100.0 * (1.0 - idleDelta / totalDelta);
  }

  Future<double> _getRAMUsage() async {
    try {
      final ProcessResult result = await Process.run('free', ['-m']);
      final lines = result.stdout.toString().split('\n');

      for (var line in lines) {
        if (line.startsWith('Mem:')) {
          final parts =
              line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          if (parts.length >= 3) {
            final total = double.parse(parts[1]);
            final used = double.parse(parts[2]);
            return (used / total) * 100;
          }
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting RAM usage: $e');
      return 0.0;
    }
  }

  Future<double> _getCPUTemperature() async {
    try {
      final file = File('/sys/class/thermal/thermal_zone0/temp');
      final temp = await file.readAsString();
      // Convert millidegrees to degrees
      return double.parse(temp.trim()) / 1000.0;
    } catch (e) {
      logger.warning('Error getting CPU temperature: $e');
      return 0.0;
    }
  }

  Future<int> _getSystemUptime() async {
    try {
      final uptimeFile = File('/proc/uptime');
      final uptimeContent = await uptimeFile.readAsString();
      final uptime = double.parse(uptimeContent.split(' ')[0]);
      return uptime.round();
    } catch (e) {
      logger.warning('Error getting system uptime: $e');
      return 0;
    }
  }

  // Consolidated method to collect all system metrics at once
  Future<Map<String, dynamic>> _collectSystemMetrics() async {
    final metrics = <String, dynamic>{
      'cpuUsage': 0.0,
      'ramUsage': 0.0,
      'gpuUsage': 0.0,
      'cpuTemp': 0.0,
      'gpuTemp': 0.0,
      'uptime': 0,
    };

    // Group commands that can be run in parallel
    final results = await Future.wait([
      // Group 1: Get CPU and RAM in one command
      Process.run('sh', ['-c', 'top -bn1 && free -m']),

      // Group 2: GPU metrics (already optimized)
      _getGPUMetrics(),

      // Group 3: Read system files only (removed Chromium check)
      Future(() async {
        final cpuTempFuture = _getCPUTemperature(); // File read
        final uptimeFuture = _getSystemUptime(); // File read

        return {
          'cpuTemp': await cpuTempFuture,
          'uptime': await uptimeFuture,
        };
      }),
    ]);

    // Parse CPU and RAM data from the combined command output
    final topAndFreeOutput = results[0] as ProcessResult;
    if (topAndFreeOutput.exitCode == 0) {
      final lines = topAndFreeOutput.stdout.toString().split('\n');

      // Parse CPU usage
      for (var line in lines) {
        if (line.contains('%Cpu(s)')) {
          final idleMatch = RegExp(r'(\d+[.,]\d+)\s*id').firstMatch(line);
          if (idleMatch != null) {
            final idle = double.parse(idleMatch.group(1)!.replaceAll(',', '.'));
            metrics['cpuUsage'] = 100 - idle;
            break;
          }
        }
      }

      // Parse RAM usage
      for (var line in lines) {
        if (line.startsWith('Mem:')) {
          final parts =
              line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          if (parts.length >= 3) {
            final total = double.parse(parts[1]);
            final used = double.parse(parts[2]);
            metrics['ramUsage'] = (used / total) * 100;
            break;
          }
        }
      }
    }

    // GPU metrics (already in the right format)
    final gpuMetrics = results[1] as Map<String, double>;
    metrics['gpuUsage'] = gpuMetrics['usage'] ?? 0.0;
    metrics['gpuTemp'] = gpuMetrics['temp'] ?? 0.0;

    // File read results
    final fileResults = results[2] as Map<String, dynamic>;
    metrics['cpuTemp'] = fileResults['cpuTemp'];
    metrics['uptime'] = fileResults['uptime'];

    return metrics;
  }

  Future<void> _reportHardwareSpecs() async {
    if (_hasReportedSpecs) return;

    try {
      // Collect RAM and screen info in parallel
      final results = await Future.wait([
        _getTotalRAM(),
        _getScreenInfo(),
      ]);

      final totalRam = results[0] as double;
      final screenInfo = results[1] as ScreenInfo;
      final softwareVersion = Environment.appVersion;

      logger.info('Hardware specs - '
          'Total RAM: ${(totalRam / 1024).toStringAsFixed(2)}GB, '
          'Screen: ${screenInfo.width}x${screenInfo.height} '
          '(${screenInfo.connected ? "connected" : "disconnected"})');

      // Send hardware specs as a separate metric event
      MetricService().sendEvent(
        'hardware_specs',
        stringData: [softwareVersion],
        doubleData: [
          totalRam,
          screenInfo.width,
          screenInfo.height,
          screenInfo.connected ? 1.0 : 0.0,
        ],
      );

      _hasReportedSpecs = true;
    } catch (e) {
      logger.severe('Error reporting hardware specs: $e');
    }
  }

  Future<double> _getTotalRAM() async {
    try {
      final ProcessResult result = await Process.run('free', ['-m']);
      final lines = result.stdout.toString().split('\n');

      for (var line in lines) {
        if (line.startsWith('Mem:')) {
          final parts =
              line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          if (parts.length >= 2) {
            return double.parse(parts[1]); // Returns total RAM in MB
          }
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting total RAM: $e');
      return 0.0;
    }
  }

  Future<ScreenInfo> _getScreenInfo() async {
    try {
      final result = await Process.run('xrandr', ['--current']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');

        for (final line in lines) {
          // Look for connected HDMI output
          if (line.contains('HDMI') && line.contains(' connected ')) {
            // Parse current resolution
            final match = RegExp(r'(\d+)x(\d+)').firstMatch(line);
            if (match != null) {
              return ScreenInfo(
                width: double.parse(match.group(1)!),
                height: double.parse(match.group(2)!),
                connected: true,
              );
            }
          }
        }

        // If no HDMI display found, look for any connected display
        for (final line in lines) {
          if (line.contains(' connected ')) {
            final match = RegExp(r'(\d+)x(\d+)').firstMatch(line);
            if (match != null) {
              return ScreenInfo(
                width: double.parse(match.group(1)!),
                height: double.parse(match.group(2)!),
                connected: true,
              );
            }
          }
        }
      }

      // Return default values if no display info found
      return ScreenInfo(width: 0, height: 0, connected: false);
    } catch (e) {
      logger.warning('Error getting screen information: $e');
      return ScreenInfo(width: 0, height: 0, connected: false);
    }
  }

  void dispose() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    stopMetricsStreaming();
    logger.info('Hardware monitoring stopped');
  }
}

class ScreenInfo {
  final double width;
  final double height;
  final bool connected;

  ScreenInfo({
    required this.width,
    required this.height,
    required this.connected,
  });
}
