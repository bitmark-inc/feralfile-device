import 'dart:convert';

class WifiCredentials {
  final String ssid;
  final String password;

  WifiCredentials({required this.ssid, required this.password});

  factory WifiCredentials.fromJson(String jsonStr) {
    final Map<String, dynamic> data = json.decode(jsonStr);
    return WifiCredentials(
      ssid: data['ssid'],
      password: data['password'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      'password': password,
    };
  }
}
