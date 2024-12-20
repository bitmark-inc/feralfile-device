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
    _bluetoothService.startListening(_handleCredentialsReceived);
  }

  Future<void> _handleCredentialsReceived(WifiCredentials credentials) async {
    // Update status to show received credentials
    setState(() {
      _statusMessage =
          'Received SSID: ${credentials.ssid}\nConnecting to Wi-Fi...';
    });

    // Attempt to connect to WiFi
    bool connected = await WifiService.connect(credentials);

    if (connected) {
      setState(() {
        _statusMessage =
            'Connected to ${credentials.ssid}. Launching Chromium...';
      });

      // Launch Chromium after successful connection
      await ChromiumLauncher.launchChromium('https://feralfile.com');

      // Clean up and exit
      _bluetoothService.dispose();
      exit(0);
    } else {
      setState(() {
        _statusMessage = 'Failed to connect to ${credentials.ssid}';
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
