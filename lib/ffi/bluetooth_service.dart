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
      // Convert raw pointer to a large enough Uint8List.
      final rawBytes = data.asTypedList(1024);

      // Find the first null terminator.
      final terminatorIndex = rawBytes.indexOf(0);
      if (terminatorIndex == -1) {
        // No null terminator found; decode the entire buffer or handle error.
        throw Exception("No null terminator found in data.");
      }

      // Sublist up to (but not including) the null terminator.
      final trimmedBytes = rawBytes.sublist(0, terminatorIndex);

      // Decode the (potentially) trimmed bytes.
      final utf8String = utf8.decode(trimmedBytes);
      _messageController.add(utf8String);
    } catch (e) {
      _messageController.add('Error processing message: $e');
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
