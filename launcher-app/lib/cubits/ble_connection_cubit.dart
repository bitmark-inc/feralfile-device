import 'dart:async';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import 'ble_connection_state.dart';


class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();
  StreamSubscription<bool>? _internetSubscription;

  BLEConnectionCubit() : super(BLEConnectionState()) {
    // Listen to internet connectivity changes.
    _internetSubscription =
        InternetConnectivityService().onStatusChange.listen((isOnline) {
      if (isOnline) {
        // When internet is connected, update state to connected.
        if (state.status == BLEConnectionStatus.initial) {
          logger.info(
              '[BLEConnectionCubit] Internet connected, setting status to connected');
          emit(state.copyWith(status: BLEConnectionStatus.connected));
        }
      } else {
        // When internet is not connected, update state to initial.
        if (state.status == BLEConnectionStatus.connected) {
          logger.info(
              '[BLEConnectionCubit] Internet disconnected, setting status to initial');
          emit(state.copyWith(status: BLEConnectionStatus.initial));
        }
      }
    });
  }

  Future<String> _getDeviceName() async {
    return _bluetoothService.getDeviceId();
  }

  Future<void> initialize() async {
    logger.info('[BLEConnectionCubit] Initializing Bluetooth service');

    // Get device name based on MAC address
    final deviceName = await _getDeviceName();

    updateDeviceId(deviceName);

    Sentry.configureScope((scope) {
      scope.setTag('device_name', deviceName);
    });

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
      // Auto-reset from failed to initial after 10 seconds.
      Future.delayed(const Duration(seconds: 10), () {
        if (state.status == BLEConnectionStatus.failed) {
          emit(state.copyWith(status: BLEConnectionStatus.initial));
          logger.info(
              '[BLEConnectionCubit] Reset status from failed to initial after 10s');
        }
      });
    }
  }

  @override
  Future<void> close() {
    logger.info(
        '[BLEConnectionCubit] Closing cubit and disposing Bluetooth service');
    _bluetoothService.dispose();
    stopLogServer();
    WebSocketService().dispose();
    _internetSubscription?.cancel();
    return super.close();
  }
}
