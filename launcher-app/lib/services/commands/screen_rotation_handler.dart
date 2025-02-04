import 'dart:io';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';
import '../config_service.dart';

enum ScreenRotation {
  normal, // 0°
  right, // 90°
  inverted, // 180°
  left // 270°
}

class ScreenRotationHandler implements CommandHandler {
  static ScreenRotation _currentRotation = ScreenRotation.normal;
  static String? _primaryDisplay;

  Future<void> _saveRotation(String rotation) async {
    await ConfigService.updateScreenRotation(rotation);
  }

  Future<String?> _loadSavedRotation() async {
    final config = await ConfigService.loadConfig();
    return config?.screenRotation;
  }

  Future<void> _initializePrimaryDisplay() async {
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

  Future<ProcessResult> _rotateScreen(String rotation) async {
    await _initializePrimaryDisplay();

    if (_primaryDisplay != null) {
      // Use faster command with specific display
      return Process.run(
          'xrandr', ['--output', _primaryDisplay!, '--rotate', rotation]);
    } else {
      // Fallback to original command
      return Process.run('xrandr', ['-o', rotation]);
    }
  }

  Future<void> initializeRotation() async {
    await _initializePrimaryDisplay(); // Initialize display name early
    final savedRotation = await _loadSavedRotation();
    if (savedRotation != null) {
      try {
        final result = await _rotateScreen(savedRotation);
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
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    logger.info('Current rotation: $_currentRotation');

    final bool clockwise = data['clockwise'] ?? false;
    final String rotation = _getNextRotation(clockwise);
    logger.info('Next rotation: $rotation');

    try {
      final result = await _rotateScreen(rotation);
      if (result.exitCode != 0) {
        logger.warning('Failed to rotate screen: ${result.stderr}');
      } else {
        await _saveRotation(rotation);
        logger.info('Screen rotated to $rotation and saved setting');
      }

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