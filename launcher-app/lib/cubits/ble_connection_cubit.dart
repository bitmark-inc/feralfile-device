import 'dart:async';

import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/websocket_service.dart';
import 'package:feralfile/utils/version_helper.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/switcher_service.dart';
import 'ble_connection_state.dart';

class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();
  final SwitcherService _switcherService = SwitcherService();
  StreamSubscription<bool>? _internetSubscription;

  // Map to track all devices and their connection history
  final Map<String, bool> _deviceConnectionHistory = {};

  BLEConnectionCubit() : super(BLEConnectionState()) {
    // Listen to internet connectivity changes.
    _internetSubscription =
        InternetConnectivityService().onStatusChange.listen((isOnline) {
      if (isOnline) {
        // When internet is connected, update state to connected.
        if (state.status == BLEConnectionStatus.initial) {
          logger.info(
              '[BLEConnectionCubit] Internet connected, setting status to connected');
          emit(state.copyWith(
              status: BLEConnectionStatus.acceptingNewConnection));
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

    final installedVersion = await VersionHelper.getInstalledVersion();

    emit(state.copyWith(version: installedVersion));
  }

  void startListening() {
    logger.info('[BLEConnectionCubit] Starting to listen for BLE connections');
    _bluetoothService.startListening(
      _handleCredentialsReceived,
      onDeviceConnectionChanged: _handleDeviceConnectionChanged,
    );
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

      // Wait for 3 seconds then transition to accepting new connection
      await Future.delayed(const Duration(seconds: 3));
      logger.info(
          '[BLEConnectionCubit] Transitioning to accepting new connection state');

      emit(state.copyWith(
        status: BLEConnectionStatus.acceptingNewConnection,
        isProcessing: false,
      ));
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

  void _handleDeviceConnectionChanged(String deviceId, bool connected) {
    logger.info('[BLEConnectionCubit] Device $deviceId ${connected ? "connected" : "disconnected"}');

    if (connected) {
      // Check if this is a new device (never seen before)
      bool isNewDevice = !_deviceConnectionHistory.containsKey(deviceId);

      // Update device connection status in history
      _deviceConnectionHistory[deviceId] = true;

      // Log device connection history
      logger.info(
          '[BLEConnectionCubit] Device connection history: ${_deviceConnectionHistory.entries.map((e) => "${e.key}: ${e.value}").join(", ")}');

      // Only disable forced focus if this is a new device
      if (isNewDevice && _deviceConnectionHistory.length > 1) {
        _switcherService.forceFeralFileFocus(false);
        logger.info(
            '[BLEConnectionCubit] New device detected (${_deviceConnectionHistory.length} total devices), disabled forced Feral File focus');
      }

      emit(state.copyWith(
        deviceId: deviceId,
        status: BLEConnectionStatus.connected,
      ));

      // Wait for 3 seconds then transition to accepting new connection
      Future.delayed(const Duration(seconds: 3), () {
        logger.info(
            '[BLEConnectionCubit] Transitioning to accepting new connection state');
        emit(state.copyWith(
          status: BLEConnectionStatus.acceptingNewConnection,
          isProcessing: false,
        ));
      });
    } else {
      // Update device connection status in history, but don't remove
      _deviceConnectionHistory[deviceId] = false;

      logger.info(
          '[BLEConnectionCubit] Updated device connection history: ${_deviceConnectionHistory.entries.map((e) => "${e.key}: ${e.value}").join(", ")}');

      // Handle disconnection - immediately go to accepting new connection state
      emit(state.copyWith(
        status: BLEConnectionStatus.acceptingNewConnection,
        isProcessing: false,
      ));
      logger.info(
          '[BLEConnectionCubit] Device disconnected, ready for new connections');
    }
  }

  @override
  Future<void> close() {
    logger.info(
        '[BLEConnectionCubit] Closing cubit and disposing Bluetooth service');
    _deviceConnectionHistory.clear(); // Clear the device history
    _bluetoothService.dispose();
    stopLogServer();
    WebSocketService().dispose();
    _internetSubscription?.cancel();
    return super.close();
  }
}
