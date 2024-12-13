// lib/main.dart
import 'package:flutter/material.dart';
import 'package:process_run/stdio.dart';
import 'screens/waiting_screen.dart';
import 'services/bluetooth_service.dart';
import 'services/wifi_service.dart';
import 'services/chromium_launcher.dart';
import 'services/logger.dart';
import 'models/wifi_credentials.dart';

void main() {
  setupLogging();
  runApp(FeralFileApp());
}

class FeralFileApp extends StatefulWidget {
  @override
  _FeralFileAppState createState() => _FeralFileAppState();
}

class _FeralFileAppState extends State<FeralFileApp> {
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isProcessing = false;
  String _statusMessage = 'Waiting for Wi-Fi credentials via Bluetooth...';

  @override
  void initState() {
    super.initState();
    _bluetoothService.startListening(_handleBluetoothConnection);
  }

  // Handle Bluetooth connection result
  Future<void> _handleBluetoothConnection(bool success, String message) async {
    logger.info('Bluetooth Connection: $message');

    if (success) {
      // Proceed to connect to Wi-Fi
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Connecting to Wi-Fi...';
      });

      // Assume you have received the Wi-Fi credentials
      // For this example, let's create dummy credentials
      // Replace this with actual received credentials
      WifiCredentials credentials =
          WifiCredentials(ssid: 'Your_SSID', password: 'Your_Password');

      bool wifiConnected = await WifiService.connect(credentials);

      if (wifiConnected) {
        setState(() {
          _statusMessage = 'Connected to Wi-Fi. Sending confirmation...';
        });

        // Send confirmation via Bluetooth
        // await _bluetoothService.sendConnectionResult(
        //     true, 'Wi-Fi connected successfully.');

        // Disconnect and turn off Bluetooth
        _bluetoothService.dispose();

        // Launch Chromium
        await ChromiumLauncher.launchChromium('https://feralfile.com');

        // Close the Flutter app after launching Chromium
        exit(0);
      } else {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Failed to connect to Wi-Fi.';
        });

        // Send failure via Bluetooth
        // await _bluetoothService.sendConnectionResult(
        //     false, 'Failed to connect to Wi-Fi.');

        // Optionally, dispose Bluetooth service
        _bluetoothService.dispose();
      }
    } else {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Failed to receive Wi-Fi credentials.';
      });
    }
  }

  @override
  void dispose() {
    _bluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feral File',
      home: WaitingScreen(message: _statusMessage),
    );
  }
}
