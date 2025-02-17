// lib/services/bluetooth_service.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:feralfile/models/chunk.dart';
import 'package:feralfile/services/logger.dart';
import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../services/metric_service.dart';
import '../utils/varint_parser.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
  static void Function(WifiCredentials)? _onCredentialsReceived;
  static final _commandPort = ReceivePort();
  static final Map<String, Map<int, List<int>>> _chunkCommands = {};

  // Store both callbacks
  late final NativeCallable<ConnectionResultCallbackNative> _setupCallback;
  late final NativeCallable<CommandCallbackNative> _cmdCallback;

  String? _cachedDeviceId;

  BluetoothService._internal() {
    _commandService.initialize(this);
  }

  Future<bool> initialize(String deviceName) async {
    logger.info('Initializing Bluetooth service...');
    logger.info('Using device name: $deviceName');

    // Convert device name to C string
    final deviceNamePtr = deviceName.toNativeUtf8();

    try {
      int initResult = _bindings.bluetooth_init(deviceNamePtr);
      if (initResult != 0) {
        logger.warning('Failed to initialize Bluetooth service.');
        return false;
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
        return false;
      }

      logger.info('Bluetooth service started. Waiting for connections...');

      _commandPort.listen((message) {
        if (message is List) {
          CommandService().handleCommand(message[0], message[1]);
        }
      });

      return true;
    } finally {
      calloc.free(deviceNamePtr);
    }
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

      final chunkInfo = ChunkInfo.fromData(dataCopy);
      _validateChunkIndices(chunkInfo);

      logger.info('Processing chunk ${chunkInfo.index} of ${chunkInfo.total}');

      _storeChunk(chunkInfo);
      _sendChunkAcknowledgement(chunkInfo);

      // Check if we have all chunks
      if (_chunkCommands[chunkInfo.ackReplyId]!.length == chunkInfo.total) {
        _processCompleteCommand(chunkInfo);
      }
    } catch (e, stackTrace) {
      logger.severe('Error parsing command data: $e');
      logger.severe('Stack trace: $stackTrace');
    }
  }

  static void _validateChunkIndices(ChunkInfo info) {
    if (!info.isValid()) {
      throw Exception(
          'Invalid chunk indices: index=${info.index}, total=${info.total}');
    }
  }

  static void _storeChunk(ChunkInfo info) {
    _chunkCommands[info.ackReplyId] ??= {};
    _chunkCommands[info.ackReplyId]![info.index] = info.command;
  }

  static void _sendChunkAcknowledgement(ChunkInfo info) {
    logger.info('Notifying back for chunk ${info.index}');
    _instance
        .notify(info.ackReplyId, {'success': true, 'chunkIndex': info.index});
  }

  static void _processCompleteCommand(ChunkInfo info) {
    // Combine all chunks in order
    final completeCommand = _chunkCommands[info.ackReplyId]!
        .values
        .expand((chunk) => chunk)
        .toList();

    // Clean up the chunks map
    _chunkCommands.remove(info.ackReplyId);

    final (commandStrings, _) =
        VarintParser.parseToStringArray(completeCommand, 0);

    if (commandStrings.length < 2) {
      throw Exception(
          'Invalid command format: expected at least command and data');
    }

    final command = commandStrings[0];
    final commandData = commandStrings[1];
    final replyId = commandStrings.length > 2 ? commandStrings[2] : null;

    logger
        .info('Parsed complete command: "$command" with data: "$commandData"');
    if (replyId != null) {
      logger.info('Reply ID: "$replyId"');
    }

    // Send metric with cached device ID
    MetricService().sendEvent(
      'command_received',
      stringData: [command, commandData],
    );

    CommandService().handleCommand(command, commandData, replyId);
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
      final (strings, _) = VarintParser.parseToStringArray(rawBytes, 0);
      if (strings.length < 2) {
        throw Exception(
            'Invalid WiFi credentials format: expected SSID and password');
      }

      final ssid = strings[0];
      final password = strings[1];
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

  void notify(String replyID, Map<String, dynamic> payload) {
    try {
      final encodedMessage = VarintParser.encodeStringArray([
        replyID,
        jsonEncode(payload),
      ]);

      final Pointer<Uint8> data = calloc<Uint8>(encodedMessage.length);
      final bytes = data.asTypedList(encodedMessage.length);

      logger.info('Copying ${encodedMessage.length} bytes to FFI buffer');
      for (var i = 0; i < encodedMessage.length; i++) {
        bytes[i] = encodedMessage[i];
      }

      final hexString =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      logger.info('Copied bytes (hex): $hexString');

      _bindings.bluetooth_notify(data, encodedMessage.length);
      calloc.free(data);

      logger.info('Sent notification: $replyID with payload: $payload');
    } catch (e) {
      logger.severe('Error sending notification: $e');
    }
  }

  String? getMacAddress() {
    final macPtr = _bindings.bluetooth_get_mac_address();
    if (macPtr.address == 0) return null;

    final macAddress = macPtr.toDartString();
    return macAddress;
  }

  String getDeviceId() {
    // Return cached device ID if available
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final mac = getMacAddress();
    if (mac == null) {
      _cachedDeviceId = 'FF-X1-000000';
      return _cachedDeviceId!;
    }

    // Generate MD5 hash of MAC address
    final bytes = utf8.encode(mac);
    final hash = md5.convert(bytes);

    // Take first 6 bytes of hash and convert to uppercase alphanumeric
    final hashStr = hash.bytes
        .sublist(0, 6)
        .map((byte) {
          return ((byte % 36) < 10)
              ? ((byte % 36) + 48) // 0-9
              : ((byte % 36) + 55); // A-Z
        })
        .map((charCode) => String.fromCharCode(charCode))
        .join();

    _cachedDeviceId = 'FF-X1-$hashStr';
    return _cachedDeviceId!;
  }
}
