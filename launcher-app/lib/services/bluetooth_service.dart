// lib/services/bluetooth_service.dart
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:feralfile/services/logger.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../utils/varint_parser.dart';

class BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
  static void Function(WifiCredentials)? _onCredentialsReceived;
  static final _commandPort = ReceivePort();

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

    _commandPort.listen((message) {
      if (message is List) {
        CommandService().handleCommand(message[0], message[1]);
      }
    });
  }

  // Store the callback reference for cleanup
  NativeCallable<ConnectionResultCallbackNative>? _callback;

  // Static callback that can be used with FFI
  static void _staticConnectionResultCallback(
    int success,
    Pointer<Uint8> data,
    int length,
  ) {
    try {
      // Use 'length' instead of hardcoding 1024
      final rawBytes = data.asTypedList(length);

      // Print hex-encoded rawBytes
      final hexString =
          rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      logger.info('Raw bytes (hex): $hexString');

      // Now safely parse varint-encoded strings out of rawBytes
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
  static void _staticCommandCallback(
      int success, Pointer<Uint8> data, int length) {
    // Print hex representation of raw data
    final hexStringData = data
        .asTypedList(length)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    logger.info('Raw command data (hex): $hexStringData');

    // Safely copy only the valid bytes using the provided length
    final bytes = data.asTypedList(length);

    // Create a hex string for logging
    final hexString =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    logger.info('Received command after trimming data (hex): $hexString');

    try {
      // Log the first few bytes to understand the length parsing
      // logger.info('First byte (length1): 0x${bytes[0].toRadixString(16)}');
      // logger.info(
      //     'Following bytes: ${bytes.sublist(1, 7).map((b) => String.fromCharCode(b)).join()}');

      var (command, commandData, bytesRead) =
          VarintParser.parseDoubleString(bytes, 0);
      logger.info('Parsed command: "$command" with data: "$commandData"');
      logger.info('Bytes read: $bytesRead');

      CommandService().handleCommand(command, commandData);
    } catch (e, stackTrace) {
      logger.severe('Error parsing command data: $e');
      logger.severe('Stack trace: $stackTrace');
    }
  }
}
