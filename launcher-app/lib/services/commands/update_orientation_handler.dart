import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/rotate_service.dart';

import '../logger.dart';
import 'command_repository.dart';

enum ScreenOrientation {
  landscape,
  landscapeReverse,
  portrait,
  portraitReverse;

  String get name {
    switch (this) {
      case ScreenOrientation.landscape:
        return 'landscape';
      case ScreenOrientation.landscapeReverse:
        return 'landscapeReverse';
      case ScreenOrientation.portrait:
        return 'portrait';
      case ScreenOrientation.portraitReverse:
        return 'portraitReverse';
    }
  }

  static ScreenOrientation fromString(String value) {
    switch (value) {
      case 'landscape':
        return ScreenOrientation.landscape;
      case 'landscapeReverse':
        return ScreenOrientation.landscapeReverse;
      case 'portrait':
        return ScreenOrientation.portrait;
      case 'portraitReverse':
        return ScreenOrientation.portraitReverse;
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
    logger.info('Received orientation update: $orientation');
    switch (orientation) {
      case ScreenOrientation.landscape:
        RotateService.rotateScreen(ScreenRotation.normal);
        break;
      case ScreenOrientation.landscapeReverse:
        RotateService.rotateScreen(ScreenRotation.inverted);
        break;
      case ScreenOrientation.portrait:
        RotateService.rotateScreen(ScreenRotation.left);
        break;
      case ScreenOrientation.portraitReverse:
        RotateService.rotateScreen(ScreenRotation.right);
        break;
    }
    if (replyId != null) {
      bluetoothService.notify(replyId, {'success': true});
    }
  }
}
