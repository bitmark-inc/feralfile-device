// lib/services/bluetooth_service.dart
import 'dart:ffi';
import 'package:feralfile/services/logger.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../utils/varint_parser.dart';

class BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
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

    late final NativeCallable<ConnectionResultCallbackNative> setupCallback;
    late final NativeCallable<CommandCallbackNative> cmdCallback;

    setupCallback = NativeCallable<ConnectionResultCallbackNative>.listener(
      _staticConnectionResultCallback,
    );

    cmdCallback = NativeCallable<CommandCallbackNative>.listener(
      _staticCommandCallback,
    );

    int startResult = _bindings.bluetooth_start(
        setupCallback.nativeFunction, cmdCallback.nativeFunction);

    if (startResult != 0) {
      logger.warning('Failed to start Bluetooth service.');
      setupCallback.close();
      cmdCallback.close();
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
      final rawBytes = data.asTypedList(1024);
      var (ssid, password, _) = VarintParser.parseDoubleString(rawBytes, 0);

      logger
          .info('Received WiFi credentials - SSID: $ssid, password: $password');

      final credentials = WifiCredentials(ssid: ssid, password: password);

      if (_onCredentialsReceived != null) {
        _onCredentialsReceived!(credentials);
      }
    } catch (e) {
      logger.warning('Error processing WiFi credentials: $e');
    }
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

  Stream<CommandData> get commandStream => _commandService.commandStream;

  // Make callback static
  static void _staticCommandCallback(int success, Pointer<Uint8> data) {
    try {
      final rawBytes = data.asTypedList(1024);
      var (command, commandData, _) =
          VarintParser.parseDoubleString(rawBytes, 0);
      CommandService().handleCommand(command, commandData);
    } catch (e) {
      logger.warning('Error processing command: $e');
    }
  }
}
