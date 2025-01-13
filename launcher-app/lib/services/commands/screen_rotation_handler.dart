import 'dart:io';
import '../logger.dart';
import 'command_repository.dart';

enum ScreenRotation {
  normal, // 0°
  right, // 90°
  inverted, // 180°
  left // 270°
}

class ScreenRotationHandler implements CommandHandler {
  static ScreenRotation _currentRotation = ScreenRotation.normal;

  String _getNextRotation(bool clockwise) {
    final rotations = ScreenRotation.values;
    final currentIndex = rotations.indexOf(_currentRotation);
    final nextIndex = clockwise
        ? (currentIndex + 1) % rotations.length
        : (currentIndex - 1 + rotations.length) % rotations.length;

    _currentRotation = rotations[nextIndex];

    switch (_currentRotation) {
      case ScreenRotation.normal:
        return 'normal';
      case ScreenRotation.right:
        return 'right';
      case ScreenRotation.inverted:
        return 'inverted';
      case ScreenRotation.left:
        return 'left';
    }
  }

  Future<ScreenRotation> _getCurrentSystemRotation() async {
    try {
      final result = await Process.run('xrandr', ['--query']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // Look for the primary display rotation
        final rotationMatch = RegExp(r'primary .* (normal|left|right|inverted)')
            .firstMatch(output);
        if (rotationMatch != null) {
          final currentRotation = rotationMatch.group(1);
          switch (currentRotation) {
            case 'normal':
              return ScreenRotation.normal;
            case 'right':
              return ScreenRotation.right;
            case 'inverted':
              return ScreenRotation.inverted;
            case 'left':
              return ScreenRotation.left;
            default:
              return ScreenRotation.normal;
          }
        }
      }
    } catch (e) {
      logger.severe('Error getting current rotation: $e');
    }
    return ScreenRotation.normal;
  }

  @override
  Future<void> execute(Map<String, dynamic> data) async {
    // Get current system rotation first
    _currentRotation = await _getCurrentSystemRotation();

    final bool clockwise = data['clockwise'] ?? false;
    final String rotation = _getNextRotation(clockwise);

    try {
      final result = await Process.run('xrandr', ['-o', rotation]);
      if (result.exitCode != 0) {
        logger.warning('Failed to rotate screen: ${result.stderr}');
      } else {
        logger.info('Screen rotated $rotation');
      }
    } catch (e) {
      logger.severe('Error rotating screen: $e');
    }
  }
}

// Add more handlers here