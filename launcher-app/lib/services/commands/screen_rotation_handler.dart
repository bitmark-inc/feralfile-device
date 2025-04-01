import 'dart:convert';
import 'package:feralfile/generated/protos/command.pb.dart';
import 'package:feralfile/services/rotate_service.dart';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class ScreenRotationHandler implements CommandHandler {
  static ScreenRotation? _currentRotation;

  Future<ScreenRotation> _getNextRotation(bool clockwise) async {
    _currentRotation ??=
        await RotateService.loadSavedRotation() ?? ScreenRotation.normal;
    _currentRotation = _currentRotation!.next(clockwise: clockwise);
    return _currentRotation!;
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('Current rotation: $_currentRotation');

    final bool clockwise = data['clockwise'] ?? false;
    final ScreenRotation rotation = await _getNextRotation(clockwise);
    logger.info('Next rotation: $rotation');

    try {
      await RotateService.rotateScreen(rotation);
      if (replyId != null) {
        final response = CommandResponse()
          ..success = true;
        bluetoothService.notify(replyId, response);
      }
    } catch (e) {
      logger.severe('Error rotating screen: $e');
      if (replyId != null) {
        final response = CommandResponse()
          ..success = false
          ..error = e.toString();
        bluetoothService.notify(replyId, response);
      }
      rethrow;
    }
  }
}