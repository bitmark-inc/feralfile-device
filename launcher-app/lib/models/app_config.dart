import 'dart:convert';
import 'wifi_credentials.dart';

class AppConfig {
  final WifiCredentials? wifiCredentials;
  final String? screenRotation;

  AppConfig({
    this.wifiCredentials,
    this.screenRotation,
  });

  factory AppConfig.fromJson(String jsonStr) {
    final Map<String, dynamic> data = json.decode(jsonStr);
    return AppConfig(
      wifiCredentials: data['wifiCredentials'] != null
          ? WifiCredentials.fromJson(jsonEncode(data['wifiCredentials']))
          : null,
      screenRotation: data['screenRotation'],
    );
  }

  String toJson() {
    return jsonEncode({
      'wifiCredentials': wifiCredentials != null
          ? json.decode(wifiCredentials!.toJson())
          : null,
      'screenRotation': screenRotation,
    });
  }
}
