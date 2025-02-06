import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/rotate_service.dart';

import '../logger.dart';
import 'command_repository.dart';

enum ScreenOrientation {
  landscape,
  portrait;

  String get name {
    switch (this) {
      case ScreenOrientation.landscape:
        return 'landscape';
      case ScreenOrientation.portrait:
        return 'portrait';
    }
  }

  static ScreenOrientation fromString(String value) {
    switch (value) {
      case 'landscape':
        return ScreenOrientation.landscape;
      case 'portrait':
        return ScreenOrientation.portrait;
      default:
        throw ArgumentError('Invalid screen orientation: $value');
    }
  }
}

class UpdateOrientationHandler implements CommandHandler {
  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    final orientation = ScreenOrientation.fromString(data['orientation']);
    if (orientation == ScreenOrientation.landscape) {
      logger.info('Landscape orientation');
      RotateService.rotateScreen(ScreenRotation.normal);
    } else {
      logger.info('Portrait orientation');
      RotateService.rotateScreen(ScreenRotation.left);
    }
    if (replyId != null) {
      bluetoothService.notify(replyId, {'success': true});
    }
  }
}
