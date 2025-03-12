import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/commands/command_repository.dart';
import 'package:feralfile/services/wifi_service.dart';

class ScanWifiHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final timeout = data['timeout'] as int; // timeout in seconds
    await WifiService.scanWifiNetwork(
        timeout: Duration(seconds: timeout),
        onResultScan: (result) {
          if (replyId != null) {
            bluetoothService.notify(replyId, {'result': result});
          }
        });
    if (replyId != null) {
      bluetoothService.notify(replyId, {'success': true});
    }
  }
}
