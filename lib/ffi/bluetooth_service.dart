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
      int success, Pointer<Utf8> message) {
    try {
      // Add null check and proper UTF-8 decoding
      if (message.address == 0) {
        _messageController.add('Error: Received null message');
        return;
      }

      String msg;
      try {
        msg = message.toDartString();
      } catch (e) {
        // If UTF-8 conversion fails, try to decode bytes manually
        final bytes =
            message.cast<Uint8>().asTypedList(256); // Adjust size as needed
        final nullTerminator = bytes.indexOf(0);
        final validBytes =
            nullTerminator >= 0 ? bytes.sublist(0, nullTerminator) : bytes;
        msg = utf8.decode(validBytes, allowMalformed: true);
      }

      _messageController.add(msg);
    } catch (e) {
      _messageController.add('Error processing message: ${e.toString()}');
    } finally {
      // Ensure we free the memory allocated by C
      if (message.address != 0) {
        malloc.free(message);
      }
    }
    _connectionController.add(success == 1);
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
