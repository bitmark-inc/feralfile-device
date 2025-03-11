import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/hardware_monitor_service.dart';
import 'package:feralfile/services/logger.dart';
import 'command_repository.dart';

class EnableMetricsStreamingHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('Enabling hardware metrics streaming');
    HardwareMonitorService().startMetricsStreaming();

    if (replyId != null) {
      bluetoothService.notify(replyId,
          {'success': true, 'message': 'Hardware metrics streaming enabled'});
    }
  }
}

class DisableMetricsStreamingHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('Disabling hardware metrics streaming');
    HardwareMonitorService().stopMetricsStreaming();

    if (replyId != null) {
      bluetoothService.notify(replyId,
          {'success': true, 'message': 'Hardware metrics streaming disabled'});
    }
  }
}
