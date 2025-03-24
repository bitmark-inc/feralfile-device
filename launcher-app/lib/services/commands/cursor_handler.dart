import 'dart:async';
import 'dart:io';
import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

class CommandItem {
  final String command;
  final Function? onComplete;
  CommandItem(this.command, this.onComplete);
}

class CursorHandler implements CommandHandler {
  // Singleton pattern
  static final CursorHandler _instance = CursorHandler._internal();
  factory CursorHandler() => _instance;
  CursorHandler._internal();

  Process? _xdotoolProcess;
  IOSink? _stdin;
  Timer? _autoDisposeTimer;
  bool _isProcessingQueue = false;
  final List<CommandItem> _commandQueue = [];

  static const int MOVEMENT_DELAY = 1; // milliseconds
  static const int AUTO_DISPOSE_DELAY = 3000; // 3 seconds

  // Core function to process commands
  Future<void> _processCommands() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      await _ensureProcessRunning();

      while (_commandQueue.isNotEmpty) {
        final item = _commandQueue.removeAt(0);
        _stdin?.writeln(item.command);
        await Future.delayed(Duration(milliseconds: MOVEMENT_DELAY));
        item.onComplete?.call({'success': true});
      }

      // Auto dispose after 3 seconds of inactivity
      _autoDisposeTimer?.cancel();
      _autoDisposeTimer =
          Timer(Duration(milliseconds: AUTO_DISPOSE_DELAY), () => dispose());
    } finally {
      _isProcessingQueue = false;
    }
  }

  // Initialize xdotool process
  Future<void> _ensureProcessRunning() async {
    if (_xdotoolProcess != null) return;

    try {
      _xdotoolProcess = await Process.start('bash', []);
      _stdin = _xdotoolProcess?.stdin;

      // Restart process if it dies
      _xdotoolProcess?.exitCode.then((_) {
        _xdotoolProcess = null;
        _stdin = null;
      });
    } catch (e) {
      logger.severe('Failed to start xdotool process: $e');
      rethrow;
    }
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      _autoDisposeTimer?.cancel();

      if (data.isEmpty) {
        // Handle tap
        _commandQueue.add(CommandItem('xdotool click 1',
            (_) => bluetoothService.notify('tapGesture', {'success': true})));
      } else {
        // Handle movements
        final List<dynamic> movements = data['cursorOffsets'] as List<dynamic>;
        for (var movement in movements) {
          final dx = (movement['dx'] as num).toDouble();
          final dy = (movement['dy'] as num).toDouble();

          final moveX = (dx * 3).round();
          final moveY = (dy * 3).round();

          bool isLastMovement = movement == movements.last;
          _commandQueue.add(CommandItem(
              'xdotool mousemove_relative -- $moveX $moveY',
              isLastMovement
                  ? (_) => bluetoothService.notify(replyId!, {'success': true})
                  : null));
        }
      }

      _processCommands();
    } catch (e) {
      logger.severe('Error: $e');
      if (replyId != null) {
        bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
    }
  }

  Future<void> dispose() async {
    _autoDisposeTimer?.cancel();
    _commandQueue.clear();
    await _stdin?.close();
    await _xdotoolProcess?.kill();
    _xdotoolProcess = null;
    _stdin = null;
  }
}
