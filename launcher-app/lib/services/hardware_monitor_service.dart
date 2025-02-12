import 'dart:async';
import 'dart:io';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/metric_service.dart';
import 'package:feralfile/services/bluetooth_service.dart';

class HardwareMonitorService {
  static final HardwareMonitorService _instance =
      HardwareMonitorService._internal();
  Timer? _monitorTimer;
  static const _monitorInterval = Duration(minutes: 2);
  final BluetoothService _bluetoothService = BluetoothService();

  factory HardwareMonitorService() => _instance;

  HardwareMonitorService._internal();

  void startMonitoring() {
    _monitorTimer?.cancel();
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

  void dispose() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    logger.info('Hardware monitoring stopped');
  }
}
