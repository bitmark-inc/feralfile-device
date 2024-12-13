// lib/ffi/bluetooth_service.dart
import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

// Singleton class to manage Bluetooth interactions
class FFI_BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _messageController =
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

    // Set up the callback
    final callbackPointer =
        Pointer.fromFunction<ConnectionResultCallbackNative>(
      _connectionResultCallback,
    );

    // Start the Bluetooth service
    int startResult = _bindings.bluetooth_start(callbackPointer);
    if (startResult != 0) {
      _messageController.add('Failed to start Bluetooth service.');
    } else {
      _messageController
          .add('Bluetooth service started. Waiting for connections...');
    }
  }

  // The Dart callback that matches the C callback signature
  void _connectionResultCallback(int success, Pointer<Utf8> message) {
    String msg = message.toDartString();
    _messageController.add(msg);
    _connectionController.add(success == 1);
  }

  // Dispose method to clean up
  void dispose() {
    _bindings.bluetooth_stop();
    _connectionController.close();
    _messageController.close();
  }
}
