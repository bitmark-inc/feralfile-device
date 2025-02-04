import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:feralfile/services/logger.dart';

class CECService {
  static final CECService _instance = CECService._internal();
  Process? _cecProcess;
  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;
  bool _isInitialized = false;

  // CEC Remote Control Key Mapping
  static const Map<String, String> keyMapping = {
    '00': 'Select',
    '01': 'Up',
    '02': 'Down',
    '03': 'Left',
    '04': 'Right',
    '05': 'Right-Up',
    '06': 'Right-Down',
    '07': 'Left-Up',
    '08': 'Left-Down',
    '09': 'Root Menu',
    '0A': 'Setup Menu',
    '0B': 'Contents Menu',
    '0C': 'Favorite Menu',
    '0D': 'Exit',
    '20': 'Number 0',
    '21': 'Number 1',
    '22': 'Number 2',
    '23': 'Number 3',
    '24': 'Number 4',
    '25': 'Number 5',
    '26': 'Number 6',
    '27': 'Number 7',
    '28': 'Number 8',
    '29': 'Number 9',
    '2A': 'Dot',
    '2B': 'Enter',
    '2C': 'Clear',
    '2F': 'Next Favorite',
    '30': 'Channel Up',
    '31': 'Channel Down',
    '32': 'Previous Channel',
    '33': 'Sound Select',
    '34': 'Input Select',
    '35': 'Display Information',
    '36': 'Help',
    '37': 'Page Up',
    '38': 'Page Down',
    '40': 'Power',
    '41': 'Volume Up',
    '42': 'Volume Down',
    '43': 'Mute',
    '44': 'Play',
    '45': 'Stop',
    '46': 'Pause',
    '47': 'Record',
    '48': 'Rewind',
    '49': 'Fast Forward',
    '4A': 'Eject',
    '4B': 'Forward',
    '4C': 'Backward',
    '4D': 'Stop-Record',
    '4E': 'Pause-Record',
    '50': 'Angle',
    '51': 'Sub Picture',
    '52': 'Video On Demand',
    '53': 'Electronic Program Guide',
    '54': 'Timer Programming',
    '55': 'Initial Configuration',
    '60': 'Play Function',
    '61': 'Pause-Play Function',
    '62': 'Record Function',
    '63': 'Pause-Record Function',
    '64': 'Stop Function',
    '65': 'Mute Function',
    '66': 'Restore Volume Function',
    '67': 'Tune Function',
    '68': 'Select Media Function',
    '69': 'Select A/V Input Function',
    '6A': 'Select Audio Input Function',
    '6B': 'Power Toggle Function',
    '6C': 'Power Off Function',
    '6D': 'Power On Function',
    '71': 'F1 (Blue)',
    '72': 'F2 (Red)',
    '73': 'F3 (Green)',
    '74': 'F4 (Yellow)',
    '75': 'F5',
    '76': 'Data',
  };

  factory CECService() {
    return _instance;
  }

  CECService._internal();

  Future<void> initialize() async {
    if (_isInitialized) {
      logger.info('CEC service already initialized');
      return;
    }

    try {
      // Check if cec-client is available
      final result = await Process.run('which', ['cec-client']);
      if (result.exitCode != 0) {
        logger.warning('cec-client not found. CEC support will be disabled.');
        return;
      }

      // Start CEC monitoring with verbose output
      await _startCECMonitoring();
      _isInitialized = true;
      logger.info('CEC service initialized');
    } catch (e) {
      logger.severe('Failed to initialize CEC service: $e');
      await dispose();
    }
  }

  Future<void> _startCECMonitoring() async {
    try {
      // Use -d 8 for debug level to show all messages including key presses
      _cecProcess = await Process.start('cec-client', ['-d', '8', '-t', 'p']);

      // Handle stdout in background
      _stdoutSubscription =
          _cecProcess!.stdout.transform(const Utf8Decoder()).listen(
        _handleCECEvent,
        onError: (error) {
          logger.severe('CEC stdout error: $error');
        },
        cancelOnError: false,
      );

      // Handle stderr in background
      _stderrSubscription =
          _cecProcess!.stderr.transform(const Utf8Decoder()).listen(
        (data) => logger.warning('CEC Error: $data'),
        onError: (error) {
          logger.severe('CEC stderr error: $error');
        },
        cancelOnError: false,
      );

      // Handle process exit
      _cecProcess!.exitCode.then((code) {
        logger.warning('CEC process exited with code: $code');
        _isInitialized = false;
        // Attempt to restart if not intentionally disposed
        if (_cecProcess != null) {
          logger.info('Attempting to restart CEC monitoring...');
          _startCECMonitoring();
        }
      });
    } catch (e) {
      logger.severe('Error starting CEC monitoring: $e');
      await dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    logger.info('Disposing CEC service...');
    _isInitialized = false;

    // Cancel stream subscriptions
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    // Kill the process if it's still running
    if (_cecProcess != null) {
      try {
        _cecProcess!.kill();
        await _cecProcess!.exitCode;
      } catch (e) {
        logger.warning('Error killing CEC process: $e');
      }
      _cecProcess = null;
    }
  }

  void _handleCECEvent(String event) {
    try {
      // Log all CEC events
      logger.info('CEC Raw Event: $event');

      // Handle specific key events
      if (event.contains('key pressed:')) {
        _handleKeyPress(event);
      } else if (event.contains('key released:')) {
        _handleKeyRelease(event);
      } else if (event.contains('standby')) {
        _handleStandby();
      } else if (event.contains('on')) {
        _handlePowerOn();
      }
    } catch (e) {
      logger.severe('Error handling CEC event: $e');
    }
  }

  String _getKeyName(String keyCode) {
    try {
      // Convert decimal to hex for mapping lookup
      final hexCode =
          int.parse(keyCode).toRadixString(16).padLeft(2, '0').toUpperCase();
      return keyMapping[hexCode] ?? 'Unknown Key ($keyCode)';
    } catch (e) {
      logger.warning('Error converting key code: $e');
      return 'Invalid Key Code';
    }
  }

  void _handleKeyPress(String event) {
    try {
      // Extract key code and log it
      final keyMatch =
          RegExp(r'key pressed: (\w+) \((\d+)\)').firstMatch(event);
      if (keyMatch != null) {
        final rawKeyName = keyMatch.group(1);
        final keyCode = keyMatch.group(2);
        final mappedKeyName = _getKeyName(keyCode!);

        logger.info(
            'CEC Key Press - Raw Name: $rawKeyName, Code: $keyCode, Mapped Name: $mappedKeyName');

        // Log specific actions for important keys
        switch (mappedKeyName) {
          case 'Play':
            logger.info('CEC: Play command received');
            break;
          case 'Pause':
            logger.info('CEC: Pause command received');
            break;
          case 'Stop':
            logger.info('CEC: Stop command received');
            break;
          case 'Fast Forward':
            logger.info('CEC: Fast Forward command received');
            break;
          case 'Rewind':
            logger.info('CEC: Rewind command received');
            break;
          // Add more specific key handlers as needed
        }
      }
    } catch (e) {
      logger.severe('Error handling key press: $e');
    }
  }

  void _handleKeyRelease(String event) {
    try {
      // Extract key code and log it
      final keyMatch =
          RegExp(r'key released: (\w+) \((\d+)\)').firstMatch(event);
      if (keyMatch != null) {
        final rawKeyName = keyMatch.group(1);
        final keyCode = keyMatch.group(2);
        final mappedKeyName = _getKeyName(keyCode!);

        logger.info(
            'CEC Key Release - Raw Name: $rawKeyName, Code: $keyCode, Mapped Name: $mappedKeyName');
      }
    } catch (e) {
      logger.severe('Error handling key release: $e');
    }
  }

  Future<void> _handleStandby() async {
    logger.info('CEC: Handling standby command');
    try {
      await Process.run('xset', ['dpms', 'force', 'off']);
    } catch (e) {
      logger.severe('Failed to handle CEC standby: $e');
    }
  }

  Future<void> _handlePowerOn() async {
    logger.info('CEC: Handling power on command');
    try {
      await Process.run('xset', ['dpms', 'force', 'on']);
    } catch (e) {
      logger.severe('Failed to handle CEC power on: $e');
    }
  }
}
