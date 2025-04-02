import 'dart:convert';
import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/commands/command_repository.dart';
import 'package:feralfile/services/wifi_service.dart';

class ScanWifiHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data,
      BluetoothService bluetoothService, [String? replyId, UserInfo? userInfo]) async {
    final timeout = data['timeout'] as int; // timeout in seconds

    await WifiService.scanWifiNetwork(
      timeout: Duration(seconds: timeout),
      onResultScan: (result) {
        if (replyId != null && replyId.isNotEmpty) {
          // Build a JSON response for each scan result.
          final response = CommandResponse()
            ..success = true
            ..data = jsonEncode({'result': result});
          bluetoothService.notify(replyId, response);
        }
      },
    );

    if (replyId != null && replyId.isNotEmpty) {
      // Send a final JSON response indicating completion.
      final response = CommandResponse()
        ..success = true
        ..message = 'Scan complete';
      bluetoothService.notify(replyId, response);
    }
  }
}