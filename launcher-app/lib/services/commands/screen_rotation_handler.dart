import 'dart:io';
import '../logger.dart';
import 'command_repository.dart';
import '../config_service.dart';
import '../overlay_service.dart';

enum ScreenRotation {
  normal, // 0°
  right, // 90°
  inverted, // 180°
  left // 270°
}

class ScreenRotationHandler implements CommandHandler {
  static ScreenRotation _currentRotation = ScreenRotation.normal;
  final _overlayService = OverlayService();

  Future<void> _saveRotation(String rotation) async {
    await ConfigService.updateScreenRotation(rotation);
  }

  Future<String?> _loadSavedRotation() async {
    final config = await ConfigService.loadConfig();
    return config?.screenRotation;
  }

  Future<void> initializeRotation() async {
    await _overlayService.initialize();
    final savedRotation = await _loadSavedRotation();
    if (savedRotation != null) {
      try {
        final result = await Process.run('xrandr', ['-o', savedRotation]);
        if (result.exitCode != 0) {
          logger.warning('Failed to apply saved rotation: ${result.stderr}');
        } else {
          logger.info('Applied saved rotation: $savedRotation');
          // Show rotation indicator with the appropriate degrees
          _showRotationOverlay(savedRotation);
          // Update current rotation state
          switch (savedRotation) {
            case 'normal':
              _currentRotation = ScreenRotation.normal;
            case 'right':
              _currentRotation = ScreenRotation.right;
            case 'inverted':
              _currentRotation = ScreenRotation.inverted;
            case 'left':
              _currentRotation = ScreenRotation.left;
          }
        }
      } catch (e) {
        logger.severe('Error applying saved rotation: $e');
      }
    }
  }

  void _showRotationOverlay(String rotation) {
    int degrees;
    switch (rotation) {
      case 'normal':
        degrees = 0;
      case 'right':
        degrees = 90;
      case 'inverted':
        degrees = 180;
      case 'left':
        degrees = 270;
      default:
        degrees = 0;
    }
    _overlayService.showRotationIndicator(degrees);
  }

  String _getNextRotation(bool clockwise) {
    const rotations = ScreenRotation.values;
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

  @override
  Future<void> execute(Map<String, dynamic> data) async {
    logger.info('Current rotation: $_currentRotation');

    final bool clockwise = data['clockwise'] ?? false;
    final String rotation = _getNextRotation(clockwise);
    logger.info('Next rotation: $rotation');

    try {
      final result = await Process.run('xrandr', ['-o', rotation]);
      if (result.exitCode != 0) {
        logger.warning('Failed to rotate screen: ${result.stderr}');
      } else {
        _showRotationOverlay(rotation);
        await _saveRotation(rotation);
        logger.info('Screen rotated to $rotation and saved setting');
      }
    } catch (e) {
      logger.severe('Error rotating screen: $e');
    }
  }

  Future<void> triggerRotation() async {
    logger.info('Manually triggering rotation');
    await execute({'clockwise': false}); // Rotate counter-clockwise
  }
}

// Add more handlers here