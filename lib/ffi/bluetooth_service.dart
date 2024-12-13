// lib/ffi/bluetooth_service.dart
import 'dart:async';
import 'dart:ffi';
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

    // Set up the callback
    final callbackPointer =
        Pointer.fromFunction<ConnectionResultCallbackNative>(
      _staticConnectionResultCallback, // Use the static callback
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

  // Static callback that can be used with FFI
  static void _staticConnectionResultCallback(
      int success, Pointer<Utf8> message) {
    String msg = message.toDartString();
    _messageController.add(msg);
    _connectionController.add(success == 1);
  }

  void dispose() {
    _bindings.bluetooth_stop();
    _connectionController.close();
    _messageController.close();
  }
}
