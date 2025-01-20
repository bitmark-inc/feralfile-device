import 'dart:io';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class CursorHandler implements CommandHandler {
  static double screenWidth = 0;
  static double screenHeight = 0;

  static Future<void> initializeScreenDimensions() async {
    try {
      final result = await Process.run('xrandr', ['--current']);
      if (result.exitCode == 0) {
        // Parse xrandr output to get current resolution
        final output = result.stdout.toString();
        final match = RegExp(r'current (\d+) x (\d+)').firstMatch(output);
        if (match != null) {
          screenWidth = double.parse(match.group(1)!);
          screenHeight = double.parse(match.group(2)!);
          logger.info(
              'Screen dimensions initialized: ${screenWidth}x$screenHeight');
        }
      }
    } catch (e) {
      logger.severe('Error getting screen dimensions: $e');
    }
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
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
        bluetoothService.notify('tapGesture', {'success': true});
      } else {
        // Handle drag gesture (existing code)
        final List<dynamic> movements = data['cursorOffsets'] as List<dynamic>;

        for (var movement in movements) {
          final dx = (movement['dx'] as num).toDouble();
          final dy = (movement['dy'] as num).toDouble();
          final coefficientX = (movement['coefficientX'] as num).toDouble();
          final coefficientY = (movement['coefficientY'] as num).toDouble();

          // Calculate actual pixel movement with screen size scaling
          final moveX = (dx * coefficientX * screenWidth).round();
          final moveY = (dy * coefficientY * screenHeight).round();

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
        if (replyId != null) {
          bluetoothService.notify(replyId, {'success': true});
        }
      }
    } catch (e) {
      logger.severe('Error in cursor handler: $e');
      if (replyId != null) {
        bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
      rethrow;
    }
  }
}
