// lib/services/bluetooth_service.dart
import 'dart:async';
import '../ffi/bluetooth_service.dart';
import '../models/wifi_credentials.dart';
import 'wifi_service.dart';
import 'chromium_launcher.dart';
import 'dart:io';

typedef ConnectionResultCallback = void Function(bool success, String message);

class BluetoothService {
  final FFI_BluetoothService _ffiService = FFI_BluetoothService();
  ConnectionResultCallback? _callback;

  BluetoothService();

  // Initialize and start listening
  void startListening(ConnectionResultCallback callback) {
    _callback = callback;

    // Listen to connection results from FFI service
    _ffiService.onConnectionResult.listen((success) async {
      if (_callback != null) {
        _callback!(
            success,
            success
                ? 'Wi-Fi connected successfully.'
                : 'Failed to connect to Wi-Fi.');

        if (success) {
          // If connected successfully, launch Chromium
          await ChromiumLauncher.launchChromium('https://feralfile.com');

          // Optionally, exit the app
          exit(0);
        } else {
          // Handle failure (e.g., show a notification, retry, etc.)
        }
      }
    });

    // Listen to messages
    _ffiService.onMessage.listen((message) {
      print('Bluetooth Message: $message');
      // You can update the UI or handle messages as needed
    });
  }

  // Dispose resources
  void dispose() {
    _ffiService.dispose();
  }
}
