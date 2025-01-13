import 'package:feralfile/services/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import 'ble_connection_state.dart';

class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();

  BLEConnectionCubit() : super(BLEConnectionState()) {
    logger.info('[BLEConnectionCubit] Initialized');
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

      emit(state.copyWith(
        status: BLEConnectionStatus.connected,
        localIp: localIp,
      ));

      logger.info('[BLEConnectionCubit] Launching Chromium browser');
      await ChromiumLauncher.launchAndWait();
    } else {
      logger.info('[BLEConnectionCubit] Failed to connect to WiFi network');
      emit(state.copyWith(
        isProcessing: false,
        status: BLEConnectionStatus.initial,
      ));
    }
  }

  @override
  Future<void> close() {
    logger.info(
        '[BLEConnectionCubit] Closing cubit and disposing Bluetooth service');
    _bluetoothService.dispose();
    stopLogServer();
    return super.close();
  }
}
