import 'dart:convert';

import 'wifi_credentials.dart';

class AppConfig {
  final WifiCredentials? wifiCredentials;
  final String? screenRotation;
  final String deviceName;
  final ArtFraming? artFraming;

  AppConfig({
    this.wifiCredentials,
    this.screenRotation,
    this.deviceName = '',
    this.artFraming,
  });

  factory AppConfig.fromJson(String jsonStr) {
    final Map<String, dynamic> data = json.decode(jsonStr);
    return AppConfig(
      wifiCredentials: data['wifiCredentials'] != null
          ? WifiCredentials.fromJson(jsonEncode(data['wifiCredentials']))
          : null,
      screenRotation: data['screenRotation'],
      deviceName: data['deviceName'] ?? '',
      artFraming: int.tryParse(data['artFraming'] ?? '') != null
          ? ArtFraming.fromValue(int.parse(data['artFraming']))
          : null,
    );
  }

  String toJson() {
    return jsonEncode({
      'wifiCredentials': wifiCredentials != null
          ? json.decode(wifiCredentials!.toJson())
          : null,
      'screenRotation': screenRotation,
      'deviceName': deviceName,
      'artFraming': artFraming?.value.toString(),
    });
  }

  AppConfig copyWith({
    WifiCredentials? wifiCredentials,
    String? screenRotation,
    String? deviceName,
    ArtFraming? artFraming,
  }) {
    return AppConfig(
      wifiCredentials: wifiCredentials ?? this.wifiCredentials,
      screenRotation: screenRotation ?? this.screenRotation,
      deviceName: deviceName ?? this.deviceName,
      artFraming: artFraming ?? this.artFraming,
    );
  }
}

enum ArtFraming {
  fitToScreen,
  cropToFill;

  int get value {
    switch (this) {
      case ArtFraming.fitToScreen:
        return 0;
      case ArtFraming.cropToFill:
        return 1;
    }
  }

  static ArtFraming fromValue(int value) {
    switch (value) {
      case 0:
        return ArtFraming.fitToScreen;
      case 1:
        return ArtFraming.cropToFill;
      default:
        throw ArgumentError('Unknown value: $value');
    }
  }
}
