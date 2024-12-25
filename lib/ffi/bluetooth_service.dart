// lib/ffi/bluetooth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:feralfile/services/logger.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

class FFI_BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  static final StreamController<String> _messageController =
      StreamController<String>.broadcast();

  // Expose streams
  Stream<bool> get onConnectionResult => _connectionController.stream;
  Stream<String> get onMessage => _messageController.stream;

  FFI_BluetoothService() {
    _initialize();
  }

  void _initialize() {
    // Initialize the Bluetooth service
    int initResult = _bindings.bluetooth_init();
    if (initResult != 0) {
      _messageController.add('Failed to initialize Bluetooth service.');
      return;
    }

    // Set up the callback as a listener for background thread safety
    late final NativeCallable<ConnectionResultCallbackNative> callback;
    callback = NativeCallable<ConnectionResultCallbackNative>.listener(
      _staticConnectionResultCallback,
    );

    // Start the Bluetooth service
    int startResult = _bindings.bluetooth_start(callback.nativeFunction);
    if (startResult != 0) {
      _messageController.add('Failed to start Bluetooth service.');
      callback.close();
    } else {
      _messageController
          .add('Bluetooth service started. Waiting for connections...');
    }
  }

  // Store the callback reference for cleanup
  NativeCallable<ConnectionResultCallbackNative>? _callback;

  // Static callback that can be used with FFI
  static void _staticConnectionResultCallback(
      int success, Pointer<Uint8> data) {
    try {
      // Get the length of data by finding null terminator
      int length = 0;
      while (data[length] != 0) {
        length++;
      }

      // Convert raw bytes to Uint8List
      final bytes = data.asTypedList(length);

      // Decode UTF-8 and parse JSON in Dart
      final utf8String = utf8.decode(bytes);
      logger.info('received message: $utf8String');

      _messageController.add(utf8String);
    } catch (e) {
      _messageController.add('Error processing message: ${e.toString()}');
    }
  }

  void dispose() {
    _bindings.bluetooth_stop();
    _connectionController.close();
    _messageController.close();
    // Clean up the native callback
    _callback?.close();
    _callback = null;
  }
}
