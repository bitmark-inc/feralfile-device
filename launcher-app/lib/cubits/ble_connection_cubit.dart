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

  Future<String> _getDeviceName() async {
    return _bluetoothService.getDeviceId();
  }

  Future<void> initialize() async {
    logger.info('[BLEConnectionCubit] Initializing Bluetooth service');

    // Get device name based on MAC address
    final deviceName = await _getDeviceName();

    updateDeviceId(deviceName);

    // Initialize Bluetooth service with the device name with retries
    const maxRetries = 3;
    var attempt = 0;
    bool initialized = false;

    while (attempt < maxRetries && !initialized) {
      attempt++;
      logger.info(
          '[BLEConnectionCubit] Initialization attempt $attempt of $maxRetries');

      try {
        initialized = await _bluetoothService.initialize(deviceName);
        if (initialized) {
          logger.info(
              '[BLEConnectionCubit] Bluetooth service initialized successfully');
          break;
        }
      } catch (e) {
        logger.warning(
            '[BLEConnectionCubit] Initialization attempt $attempt failed: $e');
      }

      if (!initialized && attempt < maxRetries) {
        // Wait before retrying
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (!initialized) {
      logger.severe(
          '[BLEConnectionCubit] Failed to initialize Bluetooth service after $maxRetries attempts');
      emit(state.copyWith(status: BLEConnectionStatus.failed));
      return;
    }

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
