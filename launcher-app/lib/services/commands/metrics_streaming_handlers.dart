import 'dart:convert';
import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:feralfile/services/logger.dart';
import 'command_repository.dart';

class EnableMetricsStreamingHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, 
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    logger.info('Enabling hardware metrics streaming');
    HardwareMonitorService().startMetricsStreaming();

    if (replyId != null) {
      final response = CommandResponse()
        ..success = true
        ..message = 'Hardware metrics streaming enabled';
      bluetoothService.notify(replyId, response);
    }
  }
}

class DisableMetricsStreamingHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data,
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    logger.info('Disabling hardware metrics streaming');
    HardwareMonitorService().stopMetricsStreaming();

    if (replyId != null) {
      final response = CommandResponse()
        ..success = true
        ..message = 'Hardware metrics streaming disabled';
      bluetoothService.notify(replyId, response);
    }
  }
}
