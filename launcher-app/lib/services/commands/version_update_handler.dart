import 'dart:convert';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/utils/version_helper.dart';
import '../logger.dart';
import 'command_repository.dart';

class VersionUpdateHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data,
      BluetoothService bluetoothService,
      [String? replyId, UserInfo? userInfo]) async {
    try {
      await VersionHelper.updateToLatestVersion();
      if (replyId == null) {
        logger.warning('No replyId provided for version update command');
        return;
      }
      final response = CommandResponse()
        ..success = true;
      bluetoothService.notify(replyId, response);
    } catch (e) {
      logger.severe('Error updating to latest version: $e');
      if (replyId != null) {
        final response = CommandResponse()
          ..success = false
          ..error = 'Failed to update to latest version: ${e.toString()}';
        bluetoothService.notify(replyId, response);
      }
    }
  }
}
