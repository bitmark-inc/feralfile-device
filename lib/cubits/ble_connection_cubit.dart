import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:process_run/stdio.dart';
import '../models/wifi_credentials.dart';
import '../services/bluetooth_service.dart';
import '../services/wifi_service.dart';
import '../services/chromium_launcher.dart';
import 'ble_connection_state.dart';

class BLEConnectionCubit extends Cubit<BLEConnectionState> {
  final BluetoothService _bluetoothService = BluetoothService();

  BLEConnectionCubit() : super(BLEConnectionState());

  void startListening() {
    _bluetoothService.startListening(_handleCredentialsReceived);
  }

  Future<void> _handleCredentialsReceived(WifiCredentials credentials) async {
    emit(state.copyWith(
      isProcessing: true,
      statusMessage:
          'Received SSID: ${credentials.ssid}\nConnecting to Wi-Fi...',
    ));

    bool connected = await WifiService.connect(credentials);

    if (connected) {
      emit(state.copyWith(
        statusMessage:
            'Connected to ${credentials.ssid}. Launching Chromium...',
      ));

      await ChromiumLauncher.launchChromium('https://feralfile.com');
      _bluetoothService.dispose();
      exit(0);
    } else {
      emit(state.copyWith(
        isProcessing: false,
        statusMessage: 'Failed to connect to ${credentials.ssid}',
      ));
    }
  }

  @override
  Future<void> close() {
    _bluetoothService.dispose();
    return super.close();
  }
}
