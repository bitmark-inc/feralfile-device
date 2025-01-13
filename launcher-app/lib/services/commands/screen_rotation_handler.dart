import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
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
  static const String _settingsFileName = 'screen_rotation.json';

  Future<void> _saveRotation(String rotation) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_settingsFileName');
      await file.writeAsString(jsonEncode({'rotation': rotation}));
      logger.info('Saved rotation setting: $rotation');
    } catch (e) {
      logger.severe('Error saving rotation setting: $e');
    }
  }

  Future<String?> _loadSavedRotation() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_settingsFileName');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents) as Map<String, dynamic>;
        return data['rotation'] as String?;
      }
    } catch (e) {
      logger.severe('Error loading rotation setting: $e');
    }
    return null;
  }

  Future<void> initializeRotation() async {
    final savedRotation = await _loadSavedRotation();
    if (savedRotation != null) {
      try {
        final result = await Process.run('xrandr', ['-o', savedRotation]);
        if (result.exitCode != 0) {
          logger.warning('Failed to apply saved rotation: ${result.stderr}');
        } else {
          logger.info('Applied saved rotation: $savedRotation');
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
        await _saveRotation(rotation);
        logger.info('Screen rotated to $rotation and saved setting');
      }
    } catch (e) {
      logger.severe('Error rotating screen: $e');
    }
  }
}

// Add more handlers here