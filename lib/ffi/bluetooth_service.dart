// lib/ffi/bluetooth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
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
      // Convert raw pointer to a Uint8List
      final rawBytes = data.asTypedList(1024);
      var offset = 0;

      // Read SSID length (varint)
      var (ssidLength, ssidOffset) = _readVarint(rawBytes, offset);
      offset = ssidOffset;

      // Read SSID
      final ssid = ascii.decode(rawBytes.sublist(offset, offset + ssidLength));
      offset += ssidLength;

      // Read password length (varint)
      var (passwordLength, passwordOffset) = _readVarint(rawBytes, offset);
      offset = passwordOffset;

      // Read password
      final password =
          ascii.decode(rawBytes.sublist(offset, offset + passwordLength));

      // Construct message
      final message = 'Received credentials - SSID: $ssid, Password: $password';
      _messageController.add(message);
    } catch (e) {
      _messageController.add('Error processing message: $e');
    }
  }

  // Helper method to read varint
  static (int value, int newOffset) _readVarint(Uint8List bytes, int offset) {
    var value = 0;
    var shift = 0;

    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }

    return (value, offset);
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
