import 'package:feralfile/services/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:process_run/stdio.dart';
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
      statusMessage:
          'Received SSID: ${credentials.ssid}\nConnecting to Wi-Fi...',
    ));

    logger.info('[BLEConnectionCubit] Attempting to connect to WiFi network');
    bool connected = await WifiService.connect(credentials);
    logger.info('[BLEConnectionCubit] WiFi connection result: $connected');

    if (connected) {
      logger.info(
          '[BLEConnectionCubit] Successfully connected to ${credentials.ssid}');
      emit(state.copyWith(
        statusMessage:
            'Connected to ${credentials.ssid}. Launching Chromium...',
      ));

      logger.info('[BLEConnectionCubit] Launching Chromium browser');
      await ChromiumLauncher.launchChromium('https://display.feralfile.com');
      logger.info('[BLEConnectionCubit] Disposing Bluetooth service');
      _bluetoothService.dispose();
      logger.info('[BLEConnectionCubit] Exiting application');
      exit(0);
    } else {
      logger.info('[BLEConnectionCubit] Failed to connect to WiFi network');
      emit(state.copyWith(
        isProcessing: false,
        statusMessage: 'Failed to connect to ${credentials.ssid}',
      ));
    }
  }

  @override
  Future<void> close() {
    logger.info(
        '[BLEConnectionCubit] Closing cubit and disposing Bluetooth service');
    _bluetoothService.dispose();
    return super.close();
  }
}
