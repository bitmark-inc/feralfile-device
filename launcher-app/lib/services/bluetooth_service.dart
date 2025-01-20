// lib/services/bluetooth_service.dart
import 'dart:ffi';
import 'dart:isolate';
import 'package:feralfile/services/logger.dart';
import 'package:ffi/ffi.dart';
import 'dart:convert';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../utils/varint_parser.dart';

class BluetoothService {
  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
  static void Function(WifiCredentials)? _onCredentialsReceived;
  static final _commandPort = ReceivePort();

  // Store both callbacks
  late final NativeCallable<ConnectionResultCallbackNative> _setupCallback;
  late final NativeCallable<CommandCallbackNative> _cmdCallback;

  BluetoothService() {
    _commandService.initialize(this);
    _initialize();
  }

  void _initialize() {
    logger.info('Initializing Bluetooth service...');
    int initResult = _bindings.bluetooth_init();
    if (initResult != 0) {
      logger.warning('Failed to initialize Bluetooth service.');
      return;
    }

    _setupCallback = NativeCallable<ConnectionResultCallbackNative>.listener(
      _staticConnectionResultCallback,
    );

    _cmdCallback = NativeCallable<CommandCallbackNative>.listener(
      _staticCommandCallback,
    );

    int startResult = _bindings.bluetooth_start(
        _setupCallback.nativeFunction, _cmdCallback.nativeFunction);

    if (startResult != 0) {
      logger.warning('Failed to start Bluetooth service.');
      _setupCallback.close();
      _cmdCallback.close();
    } else {
      logger.info('Bluetooth service started. Waiting for connections...');
    }

    _commandPort.listen((message) {
      if (message is List) {
        CommandService().handleCommand(message[0], message[1]);
      }
    });
  }

  void startListening(void Function(WifiCredentials) onCredentialsReceived) {
    logger.info('Starting to listen for Bluetooth connections...');
    _onCredentialsReceived = onCredentialsReceived;
  }

  void dispose() {
    logger.info('Disposing Bluetooth service...');
    _bindings.bluetooth_stop();
    _setupCallback.close();
    _cmdCallback.close();
    _onCredentialsReceived = null;
  }

  Stream<CommandData> get commandStream => _commandService.commandStream;

  // Make callback static
  static void _staticCommandCallback(
      int success, Pointer<Uint8> data, int length) {
    List<int>? dataCopy;
    try {
      // Create an immediate copy of the data
      dataCopy = List<int>.unmodifiable(data.asTypedList(length));
      // Release the FFI data
      calloc.free(data);

      var (command, commandData, bytesRead) =
          VarintParser.parseDoubleString(dataCopy, 0);
      logger.info('Parsed command: "$command" with data: "$commandData"');
      logger.info('Bytes read: $bytesRead');

      CommandService().handleCommand(command, commandData);
    } catch (e, stackTrace) {
      logger.severe('Error parsing command data: $e');
      logger.severe('Stack trace: $stackTrace');
    }
  }

  // Static callback that can be used with FFI
  static void _staticConnectionResultCallback(
    int success,
    Pointer<Uint8> data,
    int length,
  ) {
    List<int>? rawBytes;
    try {
      // Create an immediate immutable copy of the data
      rawBytes = List<int>.unmodifiable(data.asTypedList(length));
      // Release the FFI data
      calloc.free(data);

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

  void notify(String command, Map<String, dynamic> payload) {
    try {
      final encodedMessage = VarintParser.encodeDoubleString(
        command,
        jsonEncode(payload),
      );

      final Pointer<Uint8> data = calloc<Uint8>(encodedMessage.length);
      final bytes = data.asTypedList(encodedMessage.length);

      logger.info(
          '[Notify] Copying ${encodedMessage.length} bytes to FFI buffer');
      for (var i = 0; i < encodedMessage.length; i++) {
        bytes[i] = encodedMessage[i];
      }
      final hexString =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      logger.info('[Notify] Copied bytes (hex): $hexString');

      _bindings.bluetooth_notify(data, encodedMessage.length);
      calloc.free(data);

      logger.info('Sent notification: $command with payload: $payload');
    } catch (e) {
      logger.severe('Error sending notification: $e');
    }
  }
}
