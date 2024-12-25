// lib/services/bluetooth_service.dart
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:convert';
import 'package:feralfile/services/logger.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';

class BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  // Make callback static
  static void Function(WifiCredentials)? _onCredentialsReceived;

  BluetoothService() {
    _initialize();
  }

  void _initialize() {
    logger.info('Initializing Bluetooth service...');
    int initResult = _bindings.bluetooth_init();
    if (initResult != 0) {
      logger.warning('Failed to initialize Bluetooth service.');
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
      logger.warning('Failed to start Bluetooth service.');
      callback.close();
    } else {
      logger.info('Bluetooth service started. Waiting for connections...');
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

      logger
          .info('Received WiFi credentials - SSID: $ssid, password: $password');

      // Create WifiCredentials object
      final credentials = WifiCredentials(ssid: ssid, password: password);

      // Notify the callback if registered
      if (_onCredentialsReceived != null) {
        _onCredentialsReceived!(credentials);
      }
    } catch (e) {
      logger.warning('Error processing WiFi credentials: $e');
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

  void startListening(void Function(WifiCredentials) onCredentialsReceived) {
    logger.info('Starting to listen for Bluetooth connections...');
    _onCredentialsReceived = onCredentialsReceived;
  }

  void dispose() {
    logger.info('Disposing Bluetooth service...');
    _bindings.bluetooth_stop();
    _callback?.close();
    _callback = null;
    _onCredentialsReceived = null;
  }
}
