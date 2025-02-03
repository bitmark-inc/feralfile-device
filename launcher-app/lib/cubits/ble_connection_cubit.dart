import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import '../services/config_service.dart';
import 'ble_connection_state.dart';
import 'dart:math';

class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();

  BLEConnectionCubit() : super(BLEConnectionState());

  String _generateRandomDeviceName() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final result =
        List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    return 'FF-X1-$result';
  }

  Future<String> _getOrGenerateDeviceName() async {
    // Try to get existing device name
    final existingName = await ConfigService.getDeviceName();
    if (existingName?.isNotEmpty == true) {
      return existingName!;
    }

    // Generate new device name if none exists
    final deviceName = _generateRandomDeviceName();
    await ConfigService.setDeviceName(deviceName);
    return deviceName;
  }

  Future<void> initialize() async {
    logger.info('[BLEConnectionCubit] Initializing Bluetooth service');

    // Get or generate device name
    final deviceName = await _getOrGenerateDeviceName();

    // Initialize Bluetooth service with the device name
    await _bluetoothService.initialize(deviceName);

    // Update state with device ID
    emit(state.copyWith(deviceId: deviceName));

    startListening();
  }

  void startListening() {
    logger.info('[BLEConnectionCubit] Starting to listen for BLE connections');
    _bluetoothService.startListening(_handleCredentialsReceived);
  }

  Future<void> _handleCredentialsReceived(WifiCredentials credentials) async {
    logger.info(
        '[BLEConnectionCubit] Credentials received - SSID: ${credentials.ssid}');

    emit(state.copyWith(
      isProcessing: true,
      status: BLEConnectionStatus.connecting,
      ssid: credentials.ssid,
    ));

    logger.info('[BLEConnectionCubit] Attempting to connect to WiFi network');
    bool connected = await WifiService.connect(credentials);
    logger.info('[BLEConnectionCubit] WiFi connection result: $connected');

    if (connected) {
      _bluetoothService.notify('wifi_connection', {'success': true});

      // Get local IP address
      final localIp = await WifiService.getLocalIpAddress();

      logger.info(
          '[BLEConnectionCubit] Successfully connected to ${credentials.ssid}');

      // Start log server after successful WiFi connection
      await startLogServer();
      logger.info('[BLEConnectionCubit] Log server started');

      // Start WebSocket server
      await WebSocketService().initServer();
      logger.info('[BLEConnectionCubit] WebSocket server started');

      emit(state.copyWith(
        status: BLEConnectionStatus.connected,
        localIp: localIp,
      ));

      logger.info('[BLEConnectionCubit] Launching Chromium browser');
      // await ChromiumLauncher.launchAndWait();
    } else {
      _bluetoothService.notify('wifi_connection', {'success': false});
      logger.info('[BLEConnectionCubit] Failed to connect to WiFi network');
      emit(state.copyWith(
        isProcessing: false,
        status: BLEConnectionStatus.failed,
      ));
    }
  }

  @override
  Future<void> close() {
    logger.info(
        '[BLEConnectionCubit] Closing cubit and disposing Bluetooth service');
    _bluetoothService.dispose();
    stopLogServer();
    WebSocketService().dispose();
    return super.close();
  }
}
