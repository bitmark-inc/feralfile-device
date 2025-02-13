import 'dart:async';
import 'dart:io';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/metric_service.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/command_service.dart';

class HardwareMonitorService {
  static final HardwareMonitorService _instance =
      HardwareMonitorService._internal();
  Timer? _monitorTimer;
  static const _monitorInterval = Duration(minutes: 2);
  final BluetoothService _bluetoothService = BluetoothService();
  final CommandService _commandService = CommandService();
  bool _hasReportedSpecs = false;

  factory HardwareMonitorService() => _instance;

  HardwareMonitorService._internal() {
    _commandService.initialize(_bluetoothService);
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _reportHardwareSpecs();
    _monitorTimer =
        Timer.periodic(_monitorInterval, (_) => _checkHardwareUsage());
    logger.info(
        'Hardware monitoring started with ${_monitorInterval.inMinutes} minute interval');
  }

  Future<void> _checkHardwareUsage() async {
    try {
      final cpuUsage = await _getCPUUsage();
      final ramUsage = await _getRAMUsage();
      final gpuUsage = await _getGPUUsage();
      final cpuTemp = await _getCPUTemperature();
      final gpuTemp = await _getGPUTemperature();

      logger.info('Hardware usage - CPU: ${cpuUsage.toStringAsFixed(2)}%, '
          'RAM: ${ramUsage.toStringAsFixed(2)}%, '
          'GPU: ${gpuUsage.toStringAsFixed(2)}%, '
          'CPU Temp: ${cpuTemp.toStringAsFixed(1)}°C, '
          'GPU Temp: ${gpuTemp.toStringAsFixed(1)}°C');

      // Send metrics
      MetricService().sendEvent(
        'hardware_usage',
        _bluetoothService.getDeviceId(),
        doubleData: [cpuUsage, ramUsage, gpuUsage, cpuTemp, gpuTemp],
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
          final idleMatch = RegExp(r'(\d+[.,]\d+)\s*ni').firstMatch(line);
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
      // For Raspberry Pi, we can check GPU temperature as a proxy for usage
      final ProcessResult result = await Process.run(
        'vcgencmd',
        ['measure_temp'],
      );

      if (result.exitCode == 0) {
        final temp = result.stdout.toString();
        final match = RegExp(r'temp=(\d+\.\d+)').firstMatch(temp);
        if (match != null) {
          final temperature = double.parse(match.group(1)!);
          // Convert temperature to a percentage (assuming max temp is 85°C)
          return (temperature / 85.0) * 100;
        }
      }
      return 0.0;
    } catch (e) {
      logger.warning('Error getting GPU usage: $e');
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
        _bluetoothService.getDeviceId(),
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
