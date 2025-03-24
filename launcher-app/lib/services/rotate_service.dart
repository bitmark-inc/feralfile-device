import 'dart:io';

import 'package:feralfile/services/config_service.dart';
import 'package:feralfile/services/logger.dart';

enum ScreenRotation {
  normal, // 0°
  right, // 90°
  inverted, // 180°
  left; // 270°

  String get name {
    switch (this) {
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

  ScreenRotation next({bool clockwise = true}) {
    const rotations = ScreenRotation.values;
    final currentIndex = rotations.indexOf(this);
    final nextIndex = clockwise
        ? (currentIndex + 1) % rotations.length
        : (currentIndex - 1 + rotations.length) % rotations.length;
    return rotations[nextIndex];
  }

  static ScreenRotation fromString(String value) {
    switch (value) {
      case 'normal':
        return ScreenRotation.normal;
      case 'right':
        return ScreenRotation.right;
      case 'inverted':
        return ScreenRotation.inverted;
      case 'left':
        return ScreenRotation.left;
      default:
        throw ArgumentError('Invalid screen rotation: $value');
    }
  }
}

class RotateService {
  static String? _primaryDisplay;

  static Future<ProcessResult> rotateScreen(
      ScreenRotation screenRotation) async {
    try {
      final result = await Process.run(
          'sudo', ['/usr/local/bin/rotate-display.sh', screenRotation.name]);

      if (result.exitCode != 0) {
        logger.warning('System rotation script failed: ${result.stderr}');
      } else {
        logger.info('Screen rotated to ${screenRotation.name}');
      }
      return result;
    } catch (e) {
      logger.severe('Error applying rotation: $e');
      return ProcessResult(1, 1, '', e.toString());
    }
  }

  // Get the current rotation from the system
  static Future<ScreenRotation> getCurrentRotation() async {
    try {
      final result = await Process.run('xrandr', ['--query', '--current']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (_primaryDisplay != null && line.startsWith(_primaryDisplay!)) {
            if (line.contains(' normal ')) return ScreenRotation.normal;
            if (line.contains(' right ')) return ScreenRotation.right;
            if (line.contains(' inverted ')) return ScreenRotation.inverted;
            if (line.contains(' left ')) return ScreenRotation.left;
          }
        }
      }
    } catch (e) {
      logger.warning('Error getting current rotation: $e');
    }
    // Default if we can't determine
    return ScreenRotation.normal;
  }
}
