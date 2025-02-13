import 'package:feralfile/environment.dart';
import 'package:feralfile/models/app_config.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/config_service.dart';
import 'package:feralfile/services/rotate_service.dart';
import 'package:feralfile/services/wifi_service.dart';

import '../logger.dart';
import 'command_repository.dart';

class DeviceInfo {
  final String version;
  final String? ipAddress;
  final String? connectedWifi;
  final ScreenRotation screenRotation;
  final ArtFraming? artFraming;
  final bool isConnectedToWifi;

  DeviceInfo({
    required this.version,
    this.ipAddress,
    this.connectedWifi,
    this.isConnectedToWifi = false,
    required this.screenRotation,
    this.artFraming,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'ipAddress': ipAddress,
      'connectedWifi': connectedWifi,
      'screenRotation': screenRotation.name,
      'isConnectedToWifi': isConnectedToWifi,
      'artFraming': artFraming?.value,
    };
  }
}

class DeviceStatusHandler implements CommandHandler {
  String _loadVersion() {
    return Environment.appVersion;
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final config = await ConfigService.loadConfig();
    final version = _loadVersion();
    final ipAddress = await WifiService.getLocalIpAddress();
    final isConnectedToWifi = await WifiService.isConnectedToWifi();
    final connectedWifi = config?.wifiCredentials?.ssid;
    final screenRotation = ScreenRotation.fromString(
        config?.screenRotation ?? ScreenRotation.normal.name);
    final artFraming = config?.artFraming;
    final deviceInfo = DeviceInfo(
      version: version,
      ipAddress: ipAddress,
      connectedWifi: connectedWifi,
      screenRotation: screenRotation,
      isConnectedToWifi: isConnectedToWifi,
      artFraming: artFraming,
    );

    if (replyId == null) {
      logger.warning('No replyId provided for version command');
      return;
    }
    bluetoothService.notify(replyId, deviceInfo.toJson());
  }
}
