import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import 'ble_connection_state.dart';
import 'dart:math';
import '../services/config_service.dart';

class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();

  BLEConnectionCubit() : super(BLEConnectionState()) {
    logger.info('[BLEConnectionCubit] Initialized');
    _generateAndSetDeviceName();
  }

  Future<void> _generateAndSetDeviceName() async {
    // Try to load existing device name
    final config = await ConfigService.loadConfig();
    String? deviceName = config?.deviceName;

    if (deviceName == null) {
      // Generate new device name if none exists
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      deviceName =
          List.generate(6, (index) => chars[rnd.nextInt(chars.length)]).join();
      deviceName = 'FF-X1 ($deviceName)';

      // Save the new device name
      await ConfigService.updateDeviceName(deviceName);
      logger.info(
          '[BLEConnectionCubit] Generated and saved new device name: $deviceName');
    } else {
      logger
          .info('[BLEConnectionCubit] Using existing device name: $deviceName');
    }

    // Set the device name in the bluetooth service
    _bluetoothService.setDeviceName(deviceName);

    // Update state with device name
    emit(state.copyWith(deviceName: deviceName));
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
