import 'package:feralfile/environment.dart';
import 'package:feralfile/models/app_config.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/config_service.dart';
import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:feralfile/services/rotate_service.dart';
import 'package:feralfile/services/wifi_service.dart';
import 'package:feralfile/utils/version_helper.dart';
import 'package:process_run/stdio.dart';

import '../logger.dart';
import 'command_repository.dart';

class DeviceInfo {
  final String version;
  final String? ipAddress;
  final String? connectedWifi;
  final ScreenRotation screenRotation;
  final ArtFraming? artFraming;
  final bool isConnectedToWifi;
  final String? timezone;
  final String? installedVersion;
  final String? latestVersion;
  final double screenWidth;
  final double screenHeight;
  final String screenBrand;
  final bool isScreenConnected;

  DeviceInfo({
    required this.version,
    this.ipAddress,
    this.connectedWifi,
    this.isConnectedToWifi = false,
    required this.screenRotation,
    this.artFraming,
    this.timezone,
    this.installedVersion,
    this.latestVersion,
    this.screenWidth = 0,
    this.screenHeight = 0,
    this.screenBrand = '',
    this.isScreenConnected = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'ipAddress': ipAddress,
      'connectedWifi': connectedWifi,
      'screenRotation': screenRotation.name,
      'isConnectedToWifi': isConnectedToWifi,
      'artFraming': artFraming?.value,
      'timezone': timezone,
      'installedVersion': installedVersion,
      'latestVersion': latestVersion,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'screenBrand': screenBrand,
      'isScreenConnected': isScreenConnected,
    };
  }
}

class DeviceStatusHandler implements CommandHandler {
  String _loadVersion() {
    return Environment.appVersion;
  }

  Future<String> getTimeZone() async {
    try {
      ProcessResult result = await Process.run(
          'timedatectl', ['show', '--property=Timezone', '--value']);

      if (result.exitCode == 0) {
        String timezone = result.stdout.toString().trim();
        return timezone;
      } else {
        logger.info("Error: ${result.stderr}");
        return "Unknown";
      }
    } catch (e) {
      logger.info("Failed to get timezone: $e");
      return "Unknown";
    }
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final config = await ConfigService.loadConfig();
    final version = _loadVersion();
    final ipAddress = await WifiService.getLocalIpAddress();
    final isConnectedToWifi = InternetConnectivityService().isOnline;
    final connectedWifi = await WifiService.getCurrentWifiSSID();
    final screenRotation = config?.screenRotation ?? ScreenRotation.normal;
    final artFraming = config?.artFraming;
    final timezone = await getTimeZone();
    final installedVersion = await VersionHelper.getInstalledVersion();
    final latestVersion = await VersionHelper.getLatestVersion();
    final screenInfo = await HardwareMonitorService.getScreenInfo();
    final deviceInfo = DeviceInfo(
      version: version,
      ipAddress: ipAddress,
      connectedWifi: connectedWifi,
      screenRotation: screenRotation,
      isConnectedToWifi: isConnectedToWifi,
      artFraming: artFraming,
      timezone: timezone,
      installedVersion: installedVersion,
      latestVersion: latestVersion,
      screenWidth: screenInfo.width,
      screenHeight: screenInfo.height,
      screenBrand: screenInfo.brand,
      isScreenConnected: screenInfo.connected,
    );

    if (replyId == null) {
      logger.warning('No replyId provided for version command');
      return;
    }
    bluetoothService.notify(replyId, deviceInfo.toJson());
  }
}
