import 'dart:async';
import 'dart:io';
import 'package:feralfile/generated/protos/system_metrics.pb.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/metric_service.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:fixnum/src/int64.dart';

class HardwareMonitorService {
  static final HardwareMonitorService _instance =
      HardwareMonitorService._internal();
  Timer? _monitorTimer;
  Timer? _streamingTimer;
  static const _monitorInterval = Duration(minutes: 1);
  static const _streamingInterval = Duration(seconds: 5);
  bool _hasReportedSpecs = false;
  bool internetConnected = InternetConnectivityService().isOnline;
  bool _isStreamingEnabled = false;
  final BluetoothService _bluetoothService = BluetoothService();

  factory HardwareMonitorService() => _instance;

  HardwareMonitorService._internal() {
    // Subscribe to connectivity changes.
    InternetConnectivityService().onStatusChange.listen((status) {
      if (status) {
        logger.info('Internet is online. Monitoring hardware.');
        internetConnected = true;
      } else {
        logger.info('Internet is offline. Pausing hardware monitoring.');
        internetConnected = false;
      }
    });
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _reportHardwareSpecs();
    _monitorTimer =
        Timer.periodic(_monitorInterval, (_) {if (internetConnected) {_checkHardwareUsage();}});
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
      final cpuUsage = await _getCPUUsage();
      final ramUsage = await _getRAMUsage();
      final gpuUsage = await _getGPUUsage();
      final cpuTemp = await _getCPUTemperature();
      final gpuTemp = await _getGPUTemperature();
      final screenInfo = await _getScreenInfo();
      final uptime = await _getSystemUptime();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create and populate the protobuf message
      final metrics = DeviceRealtimeMetrics()
        ..cpuUsage = cpuUsage
        ..memoryUsage = ramUsage
        ..gpuUsage = gpuUsage
        ..cpuTemperature = cpuTemp
        ..gpuTemperature = gpuTemp
        ..screenWidth = screenInfo.width.toInt()
        ..screenHeight = screenInfo.height.toInt()
        ..uptimeSeconds = Int64(uptime)
        ..timestamp = Int64(timestamp);

      // Serialize to binary format
      final bytes = metrics.writeToBuffer();

      // Send via Bluetooth engineering characteristic
      _bluetoothService.sendEngineeringData(bytes);

      logger.info(
          'Streamed hardware metrics - CPU: ${cpuUsage.toStringAsFixed(2)}%, '
          'RAM: ${ramUsage.toStringAsFixed(2)}%, '
          'GPU Clock: ${gpuUsage.toStringAsFixed(2)}MHz, '
          'CPU Temp: ${cpuTemp.toStringAsFixed(1)}°C, '
          'GPU Temp: ${gpuTemp.toStringAsFixed(1)}°C, '
          'Resolution: ${screenInfo.width.toInt()}x${screenInfo.height.toInt()}, '
          'Uptime: ${Duration(seconds: uptime).toString()}, '
          'Timestamp: ${DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String()}');
    } catch (e) {
      logger.severe('Error streaming hardware metrics: $e');
    }
  }

  Future<void> _checkHardwareUsage() async {
    try {
      final cpuUsage = await _getCPUUsage();
      final ramUsage = await _getRAMUsage();
      final gpuUsage = await _getGPUUsage();
      final cpuTemp = await _getCPUTemperature();
      final gpuTemp = await _getGPUTemperature();
      final isChromiumRunning = await _isChromiumRunning();

      logger.info('Hardware usage - CPU: ${cpuUsage.toStringAsFixed(2)}%, '
          'RAM: ${ramUsage.toStringAsFixed(2)}%, '
          'GPU Clock: ${gpuUsage.toStringAsFixed(2)}MHz, '
          'CPU Temp: ${cpuTemp.toStringAsFixed(1)}°C, '
          'GPU Temp: ${gpuTemp.toStringAsFixed(1)}°C, '
          'Chromium: ${isChromiumRunning ? "running" : "not running"}');

      // Send metrics
      MetricService().sendEvent(
        'hardware_usage',
        doubleData: [
          cpuUsage,
          ramUsage,
          gpuUsage,
          cpuTemp,
          gpuTemp,
          isChromiumRunning ? 1.0 : 0.0
        ],
      );
    } catch (e) {
      logger.severe('Error checking hardware usage: $e');
    }
  }

  Future<double> _getCPUUsage() async {
    try {
      final ProcessResult result = await Process.run('top', ['-bn1']);
      final lines = result.stdout.toString().split('\n');

      // Find the CPU usage line
      for (var line in lines) {
        if (line.contains('%Cpu(s)')) {
          // Extract the idle percentage
          final idleMatch = RegExp(r'(\d+[.,]\d+)\s*id').firstMatch(line);
          if (idleMatch != null) {
            final idle = double.parse(idleMatch.group(1)!.replaceAll(',', '.'));
            return 100 - idle; // Convert idle to usage percentage
          }
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting CPU usage: $e');
      return 0.0;
    }
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

  Future<double> _getGPUUsage() async {
    try {
      // Get GPU clock frequency
      final ProcessResult result = await Process.run(
        'vcgencmd',
        ['measure_clock', 'v3d'],
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // Output format is "frequency(1)=XXXXX"
        final match = RegExp(r'=(\d+)').firstMatch(output);
        if (match != null) {
          final clockSpeedHz = double.parse(match.group(1)!);
          // Convert Hz to MHz
          return clockSpeedHz / 1000000.0;
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting GPU clock speed: $e');
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

  Future<double> _getGPUTemperature() async {
    try {
      final ProcessResult result = await Process.run(
        'vcgencmd',
        ['measure_temp'],
      );

      if (result.exitCode == 0) {
        final temp = result.stdout.toString();
        final match = RegExp(r'temp=(\d+\.\d+)').firstMatch(temp);
        if (match != null) {
          return double.parse(match.group(1)!);
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting GPU temperature: $e');
      return 0.0;
    }
  }

  Future<void> _reportHardwareSpecs() async {
    if (_hasReportedSpecs) return;

    try {
      final totalRam = await _getTotalRAM();
      final screenInfo = await _getScreenInfo();

      logger.info('Hardware specs - '
          'Total RAM: ${(totalRam / 1024).toStringAsFixed(2)}GB, '
          'Screen: ${screenInfo.width}x${screenInfo.height} '
          '(${screenInfo.connected ? "connected" : "disconnected"})');

      // Send hardware specs as a separate metric event
      MetricService().sendEvent(
        'hardware_specs',
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

  Future<bool> _isChromiumRunning() async {
    try {
      final ProcessResult result =
          await Process.run('pgrep', ['-f', 'chromium']);
      return result.exitCode == 0;
    } catch (e) {
      logger.warning('Error checking Chromium status: $e');
      return false;
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
