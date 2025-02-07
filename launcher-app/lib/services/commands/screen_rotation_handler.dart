import 'package:feralfile/services/rotate_service.dart';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class ScreenRotationHandler implements CommandHandler {
  static ScreenRotation _currentRotation = ScreenRotation.normal;

  ScreenRotation _getNextRotation(bool clockwise) {
    _currentRotation = _currentRotation.next(clockwise: clockwise);
    return _currentRotation;
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('Current rotation: $_currentRotation');

    final bool clockwise = data['clockwise'] ?? false;
    final ScreenRotation rotation = _getNextRotation(clockwise);
    logger.info('Next rotation: $rotation');

    try {
      await RotateService.rotateScreen(rotation);
      // Send success notification
      if (replyId != null) {
        bluetoothService.notify(replyId, {'success': true});
      }
    } catch (e) {
      logger.severe('Error rotating screen: $e');
      if (replyId != null) {
        bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
      rethrow;
    }
  }
}

// Add more handlers here
