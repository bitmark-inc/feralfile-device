import 'dart:io';
import '../logger.dart';
import 'command_repository.dart';

class CursorHandler implements CommandHandler {
  @override
  Future<void> execute(Map<String, dynamic> data) async {
    try {
      // Check if this is a tap or drag gesture based on the command type
      if (data.isEmpty) {
        // Handle tap gesture - simple click at current position
        final result = await Process.run('xdotool', ['click', '1']);
        if (result.exitCode != 0) {
          logger.warning('Failed to perform tap click: ${result.stderr}');
          return;
        }

        logger.info('Tap gesture executed');
      } else {
        // Handle drag gesture (existing code)
        final List<dynamic> movements = data['movements'] as List<dynamic>;

        for (var movement in movements) {
          final dx = (movement['dx'] as num).toDouble();
          final dy = (movement['dy'] as num).toDouble();
          final coefficientX = (movement['coefficientX'] as num).toDouble();
          final coefficientY = (movement['coefficientY'] as num).toDouble();

          // Calculate actual pixel movement
          final moveX = (dx * coefficientX).round();
          final moveY = (dy * coefficientY).round();

          // Use xdotool to move mouse relative to current position
          final result = await Process.run('xdotool', [
            'mousemove_relative',
            '--', // Required for negative values
            moveX.toString(),
            moveY.toString()
          ]);

          if (result.exitCode != 0) {
            logger.warning('Failed to move cursor: ${result.stderr}');
            break;
          }
        }

        logger.info('Cursor movement completed');
      }
    } catch (e) {
      logger.severe('Error processing cursor movement: $e');
    }
  }
}
