import 'dart:io';
import '../logger.dart';
import 'command_repository.dart';

class ScreenRotationHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    final bool clockwise = data['clockwise'] ?? false;
    final String rotation = clockwise ? 'right' : 'left';

    try {
      final result = await Process.run('xrandr', ['-o', rotation]);
      if (result.exitCode != 0) {
        logger.warning('Failed to rotate screen: ${result.stderr}');
      } else {
        logger.info('Screen rotated $rotation');
      }
    } catch (e) {
      logger.warning('Error rotating screen: $e');
    }
  }
}

// Add more handlers here