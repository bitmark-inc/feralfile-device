// lib/services/bluetooth_service.dart
import 'dart:async';
import 'package:feralfile/services/logger.dart';

import '../ffi/bluetooth_service.dart';
import '../models/wifi_credentials.dart';
import 'wifi_service.dart';
import 'chromium_launcher.dart';
import 'dart:io';

class BluetoothService {
  final FFI_BluetoothService _ffiService = FFI_BluetoothService();
  void Function(WifiCredentials)? _onCredentialsReceived;

  void startListening(void Function(WifiCredentials) onCredentialsReceived) {
    _onCredentialsReceived = onCredentialsReceived;

    _ffiService.onMessage.listen((jsonStr) {
      try {
        // Parse the received WiFi credentials
        WifiCredentials credentials = WifiCredentials.fromJson(jsonStr);

        // Callback with the credentials
        if (_onCredentialsReceived != null) {
          _onCredentialsReceived!(credentials);
        }
      } catch (e) {
        logger.warning('Failed to parse WiFi credentials: $e');
      }
    });
  }

  void dispose() {
    _ffiService.dispose();
  }
}
