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

  static Future<void> _saveRotation(ScreenRotation rotation) async {
    await ConfigService.updateScreenRotation(rotation);
  }

  static Future<ScreenRotation?> loadSavedRotation() async {
    final config = await ConfigService.loadConfig();
    final rotation = config?.screenRotation;
    if (rotation != null) {
      logger.info('Loaded saved rotation: $rotation');
      return rotation;
    }
    return null;
  }

  static Future<void> _initializePrimaryDisplay() async {
    if (_primaryDisplay != null) return;

    try {
      final result = await Process.run('xrandr', ['--query', '--current']);
      if (result.exitCode == 0) {
        // Parse output to find primary display
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains(' connected') && line.contains(' primary ')) {
            _primaryDisplay = line.split(' ')[0];
            logger.info('Primary display detected: $_primaryDisplay');
            break;
          }
        }
      }

      if (_primaryDisplay == null) {
        logger.warning(
            'Could not detect primary display, falling back to default xrandr command');
      }
    } catch (e) {
      logger.severe('Error detecting primary display: $e');
    }
  }

  static Future<ProcessResult> rotateScreen(
      ScreenRotation screenRotation) async {
    await _initializePrimaryDisplay();
    final ProcessResult result;
    final rotation = screenRotation.name;
    if (_primaryDisplay != null) {
      // Use faster command with specific display
      result = await Process.run(
          'xrandr', ['--output', _primaryDisplay!, '--rotate', rotation]);
    } else {
      // Fallback to original command
      result = await Process.run('xrandr', ['-o', rotation]);
    }

    if (result.exitCode != 0) {
      logger.warning('Failed to rotate screen: ${result.stderr}');
    } else {
      await _saveRotation(screenRotation);
      logger.info('Screen rotated to $rotation and saved setting');
    }

    return result;
  }

  static Future<void> initializeRotation() async {
    await _initializePrimaryDisplay(); // Initialize display name early
    final savedRotation = await loadSavedRotation();
    if (savedRotation != null) {
      try {
        final result = await rotateScreen(savedRotation);
        if (result.exitCode != 0) {
          logger.warning('Failed to rotate screen: ${result.stderr}');
        } else {
          await _saveRotation(savedRotation);
          logger.info('Screen rotated to $savedRotation and saved setting');
        }
      } catch (e) {
        logger.severe('Error applying saved rotation: $e');
      }
    }
  }
}
