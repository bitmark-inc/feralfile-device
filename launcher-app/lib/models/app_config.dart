import 'dart:convert';
import 'wifi_credentials.dart';

class AppConfig {
  final WifiCredentials? wifiCredentials;
  final String? screenRotation;
  final String? deviceName;

  AppConfig({
    this.wifiCredentials,
    this.screenRotation,
    this.deviceName,
  });

  String toJson() => jsonEncode({
        'wifiCredentials': wifiCredentials?.toJson(),
        'screenRotation': screenRotation,
        'deviceName': deviceName,
      });

  factory AppConfig.fromJson(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return AppConfig(
      wifiCredentials: json['wifiCredentials'] != null
          ? WifiCredentials.fromJson(json['wifiCredentials'])
          : null,
      screenRotation: json['screenRotation'],
      deviceName: json['deviceName'],
    );
  }
}
