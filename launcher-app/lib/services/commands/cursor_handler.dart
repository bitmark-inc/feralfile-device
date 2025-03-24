import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../bluetooth_service.dart';
import '../logger.dart';
import 'command_repository.dart';

// Di chuyển CommandItem ra ngoài
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

  static double screenWidth = 0;
  static double screenHeight = 0;

  Process? _xdotoolProcess;
  IOSink? _stdin;
  bool _isInitialized = false;

  // Cập nhật kiểu Queue
  final Queue<CommandItem> _commandQueue = Queue<CommandItem>();
  bool _isProcessingQueue = false;

  // Thêm hằng số để điều chỉnh thời gian giữa các movements
  static const int MOVEMENT_DELAY = 1; // milliseconds (~60fps)

  // Xử lý queue an toàn
  Future<void> _processCommandQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_commandQueue.isNotEmpty) {
        final item = _commandQueue.removeFirst();
        try {
          logger.info('Processing command: ${item.command}');
          if (_stdin != null) {
            _stdin!.writeln(item.command);
            // Đợi một khoảng thời gian ngắn trước khi xử lý movement tiếp theo
            await Future.delayed(Duration(milliseconds: MOVEMENT_DELAY));
            item.onComplete?.call({'ok': true});
          } else {
            logger.severe('stdin is null, cannot write command');
            item.onComplete?.call({'ok': false, 'error': 'stdin is null'});
          }
        } catch (e) {
          logger.severe('Error processing command: $e');
          item.onComplete?.call({'ok': false, 'error': e.toString()});
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // Khởi tạo một lần duy nhất
  Future<void> initialize() async {
    if (_isInitialized) return;

    await initializeScreenDimensions();
    await initializeProcess();
    _isInitialized = true;
  }

  static Future<void> initializeScreenDimensions() async {
    try {
      final result = await Process.run('xrandr', ['--current']);
      if (result.exitCode == 0) {
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

  Future<void> initializeProcess() async {
    try {
      if (_xdotoolProcess != null) {
        await dispose(); // Cleanup existing process if any
      }
      _xdotoolProcess = await Process.start('bash', []);
      _stdin = _xdotoolProcess?.stdin;

      _xdotoolProcess!.stdout.transform(utf8.decoder).listen((data) {
        logger.info("xdotool output: $data");
      });

      _xdotoolProcess!.stderr.transform(utf8.decoder).listen((data) {
        logger.info("xdotool error: $data");
      });

      // Theo dõi process death để tự động khởi tạo lại
      _xdotoolProcess?.exitCode.then((_) {
        logger.info('Xdotool process died');
        _isInitialized = false;
        initialize(); // Tự động khởi tạo lại nếu process die
      });

      logger.info('Xdotool process initialized');
    } catch (e) {
      logger.severe('Error initializing xdotool process: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  Future<void> execute(
      Map<String, dynamic> data, BluetoothService bluetoothService,
      [String? replyId]) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_xdotoolProcess == null || _stdin == null) {
        await initializeProcess();
      }

      void notifyComplete(Map<String, dynamic> result) {
        if (replyId != null) {
          bluetoothService.notify(replyId, result);
        }
      }

      if (data.isEmpty) {
        // Xử lý tap gesture
        _commandQueue.add(CommandItem('xdotool click 1',
            (_) => bluetoothService.notify('tapGesture', {'success': true})));
      } else {
        final List<dynamic> movements = data['cursorOffsets'] as List<dynamic>;

        // Thay vì join tất cả movements thành một command
        // Tạo command riêng cho từng movement
        for (var movement in movements) {
          final dx = (movement['dx'] as num).toDouble();
          final dy = (movement['dy'] as num).toDouble();

          final coefficientX = (movement['coefficientX'] as num).toDouble();
          final coefficientY = (movement['coefficientY'] as num).toDouble();

          // Calculate actual pixel movement with screen size scaling
          final moveX = (dx * 3).round();
          final moveY = (dy * 3).round();

          final command = 'xdotool mousemove_relative -- $moveX $moveY';

          // Chỉ notify complete ở movement cuối cùng
          bool isLastMovement = movement == movements.last;
          _commandQueue.add(
              CommandItem(command, isLastMovement ? notifyComplete : null));
        }
      }

      // Trigger queue processing
      _processCommandQueue();
    } catch (e) {
      logger.severe('Error in cursor handler: $e');
      if (replyId != null) {
        bluetoothService
            .notify(replyId, {'success': false, 'error': e.toString()});
      }
      rethrow;
    }
  }

  // Thêm method để clear queue trong trường hợp cần thiết
  void clearCommandQueue() {
    _commandQueue.clear();
    logger.info('Command queue cleared');
  }

  @override
  Future<void> dispose() async {
    try {
      clearCommandQueue();
      await _stdin?.close();
      await _xdotoolProcess?.kill();
      _xdotoolProcess = null;
      _stdin = null;
      _isInitialized = false;
    } catch (e) {
      logger.severe('Error disposing cursor handler: $e');
    }
  }
}
