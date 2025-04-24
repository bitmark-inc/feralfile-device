// lib/services/bluetooth_service.dart

import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:feralfile/models/chunk.dart';
import 'package:feralfile/services/commands/javascript_handler.dart';
import 'package:feralfile/services/logger.dart';
import 'package:ffi/ffi.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../services/metric_service.dart';
import '../utils/varint_parser.dart';

const statusChangedReplyId = 'statusChanged';

class _DeviceConnectionArgs {
  final String deviceId;
  final bool isConnected;
  _DeviceConnectionArgs(this.deviceId, this.isConnected);
}

class _CredentialsArgs {
  final WifiCredentials credentials;
  _CredentialsArgs(this.credentials);
}

class _FfiErrorArgs {
  final String context;
  final Object error;
  final StackTrace? stackTrace;
  _FfiErrorArgs(this.context, this.error, [this.stackTrace]);
}

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
  static void Function(WifiCredentials)? _onCredentialsReceived;
  static void Function(String, bool)? _onDeviceConnectionChanged;

  static final _commandPort = ReceivePort();
  final ReceivePort _ffiCallbackPort = ReceivePort();
  late final SendPort _ffiCallbackSendPort;

  static final Map<String, Map<int, List<int>>> _chunkData = {};
  static final Set<String> chunkedResponseReplyIds = {};

  // Store callbacks
  late final NativeCallable<ConnectionResultCallbackNative> _setupCallback;
  late final NativeCallable<CommandCallbackNative> _cmdCallback;
  late final NativeCallable<DeviceConnectionCallbackNative> _connectionCallback;

  String? _cachedDeviceId;

  BluetoothService._internal() {
    _commandService.initialize(this);
    _ffiCallbackSendPort = _ffiCallbackPort.sendPort;
    _ffiCallbackPort.listen(_handleFFICallback);
    _bindings.bluetooth_set_logfile(systemLogFilePath.toNativeUtf8());
  }

  void _handleFFICallback(dynamic message) {
    print('++++++ Main Isolate: _handleFFICallback RECEIVED message type: ${message.runtimeType} ++++++');
    try {
      if (message is _DeviceConnectionArgs) {
        print('++++++ Main Isolate: _handleFFICallback PROCESSING _DeviceConnectionArgs ++++++');
        if (_onDeviceConnectionChanged == null) {
          print('++++++ Main Isolate: _onDeviceConnectionChanged IS NULL ++++++');
        } else {
          print('++++++ Main Isolate: Calling _onDeviceConnectionChanged... ++++++');
          logger.info(
            '[MainIsolate] Device ${message.isConnected ? "connected" : "disconnected"}: ${message.deviceId}');
          _onDeviceConnectionChanged!(message.deviceId, message.isConnected); // <--- 呼叫 Cubit 的處理函式
          print('++++++ Main Isolate: FINISHED calling _onDeviceConnectionChanged ++++++'); // <-- 觀察這行
        }
      }
      // **** Receive ChunkInfo object ****
      else if (message is ChunkInfo) {
        // Process command chunk logic safely on the main isolate
        _processCommandChunk(message); // Pass the whole ChunkInfo
      }
      // ****
      else if (message is _CredentialsArgs) {
        logger.info(
            '[MainIsolate] Received WiFi credentials - SSID: ${message.credentials.ssid}');
        _onCredentialsReceived?.call(message.credentials);
      } else if (message is _FfiErrorArgs) {
        logger.severe('[MainIsolate] Error from FFI callback (${message.context}): ${message.error}');
        if (message.stackTrace != null) {
           logger.severe('Stack trace: ${message.stackTrace}');
        }
      }
    } catch (e, stackTrace) {
      print('++++++ Main Isolate: ERROR in _handleFFICallback: $e \n$stackTrace ++++++');
       logger.severe('[MainIsolate] Error handling FFI callback message: $e');
       logger.severe('Stack trace: $stackTrace');
    }
  }
  
  void _processCommandChunk(ChunkInfo chunkInfo) {
     try {
       // ChunkInfo.isValid() could be called here or assumed valid if parsed ok
       // No longer need _validateChunkIndices if ChunkInfo.fromData handles errors
       logger.info('[MainIsolate] Processing chunk ${chunkInfo.index} of ${chunkInfo.total} for ${chunkInfo.ackReplyId}');

       // Use the data directly from chunkInfo
       _storeChunk(chunkInfo);
       _sendChunkAcknowledgement(chunkInfo); // Calls instance method notify

       // Check if complete using chunkInfo.total
       if (_chunkData[chunkInfo.ackReplyId]?.length == chunkInfo.total) {
         _processCompleteCommand(chunkInfo.ackReplyId); // Pass only the ID needed to retrieve data
       }
     } catch (e, stackTrace) {
        logger.severe('[MainIsolate] Error processing command chunk: $e');
        logger.severe('Stack trace: $stackTrace');
        notify(chunkInfo.ackReplyId, {'success': false, 'error': e.toString(), 'chunkIndex': chunkInfo.index});
     }
  }

  Future<bool> initialize(String deviceName) async {
    logger.info('Initializing Bluetooth service...');
    logger.info('Using device name: $deviceName');

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

      _connectionCallback =
          NativeCallable<DeviceConnectionCallbackNative>.listener(
        _staticDeviceConnectionCallback,
      );

      int startResult = _bindings.bluetooth_start(_setupCallback.nativeFunction,
          _cmdCallback.nativeFunction, _connectionCallback.nativeFunction);

      if (startResult != 0) {
        logger.warning('Failed to start Bluetooth service.');
        _setupCallback.close();
        _cmdCallback.close();
        _connectionCallback.close();
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

  void startListening(
    void Function(WifiCredentials) onCredentialsReceived, {
    void Function(String, bool)? onDeviceConnectionChanged,
  }) {
    logger.info('Starting to listen for Bluetooth connections...');
    _onCredentialsReceived = onCredentialsReceived;
    _onDeviceConnectionChanged = onDeviceConnectionChanged;
  }

  static void _staticDeviceConnectionCallback(
      Pointer<Utf8> deviceId, int connected) {
        print('****** FFI CB ENTERED: _staticDeviceConnectionCallback ******');
    try {
      final deviceIdStr = deviceId.toDartString();
      final isConnected = connected != 0;
      logger.info(
        'Device ${isConnected ? "connected" : "disconnected"}: $deviceIdStr');
        print('****** FFI CB SENDING: deviceId=$deviceIdStr, connected=$isConnected ******');
      _instance._ffiCallbackSendPort.send(_DeviceConnectionArgs(deviceIdStr, isConnected));
      print('****** FFI CB SENT SUCCESSFULLY ******'); 
    } catch (e, stackTrace) {
       print('****** FFI CB ERROR during send: $e \n$stackTrace ******');
       _instance._ffiCallbackSendPort.send(_FfiErrorArgs('DeviceConnectionCallback', e, stackTrace));
    }
  }

  void dispose() {
    logger.info('Disposing Bluetooth service...');
    _bindings.bluetooth_stop();
    _setupCallback.close();
    _cmdCallback.close();
    _connectionCallback.close();
    _ffiCallbackPort.close();
    _onCredentialsReceived = null;
    _onDeviceConnectionChanged = null;
    _commandPort.close();
  }

  Stream<CommandData> get commandStream => _commandService.commandStream;

  // Make callback static
  static void _staticCommandCallback(
      int success, Pointer<Uint8> data, int length) {
    List<int>? dataCopy;
    try {
      // Check if we have valid data
      if (data == nullptr || length <= 0) {
        logger.warning('Received empty or invalid command data');
        return;
      }

      // Create an immediate copy of the data
      dataCopy = List<int>.unmodifiable(data.asTypedList(length));

      // Release the FFI data using C's free function
      _instance._bindings.bluetooth_free_data(data);

      // Check if we have enough data to parse
      if (dataCopy.isEmpty) {
        logger.warning('Empty data after copying');
        return;
      }

      final chunkInfo = ChunkInfo.fromData(dataCopy);
      _validateChunkIndices(chunkInfo);

      logger.info('Processing chunk ${chunkInfo.index} of ${chunkInfo.total}');

      // *** Send the parsed ChunkInfo object to main isolate ***
      _instance._ffiCallbackSendPort.send(chunkInfo);
    } catch (e, stackTrace) {
      _instance._ffiCallbackSendPort.send(_FfiErrorArgs('CommandCallback', e, stackTrace));
    }
  }

  static void _validateChunkIndices(ChunkInfo info) {
    if (!info.isValid()) {
      throw Exception(
          'Invalid chunk indices: index=${info.index}, total=${info.total}');
    }
  }

  static void _storeChunk(ChunkInfo info) {
    _chunkData[info.ackReplyId] ??= {};
    _chunkData[info.ackReplyId]![info.index] = info.data;
  }

  static void _sendChunkAcknowledgement(ChunkInfo info) {
    logger.info('[MainIsolate] Notifying back for chunk ${info.index}');
    _instance
        .notify(info.ackReplyId, {'success': true, 'chunkIndex': info.index});
  }

  void _processCompleteCommand(String ackReplyId) {
    // Combine all chunks in order
    final commandMap = _chunkData[ackReplyId];

    if (commandMap == null) {
      logger.warning('[MainIsolate] No chunk data found for ackReplyId: $ackReplyId during completion.');
      notify(ackReplyId, {'success': false, 'error': 'Internal error: Missing chunk data'});
      return;
    }
    logger.info('[MainIsolate] Assembling complete command for $ackReplyId');

    // Combine all chunks in order
    final orderedChunks = commandMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final completeCommandBytes = orderedChunks.expand((entry) => entry.value).toList();

    // Clean up the chunks map
    _chunkData.remove(ackReplyId);

    try {
      final (commandStrings, _) =
          VarintParser.parseToStringArray(completeCommandBytes, 0);

      if (commandStrings.length < 2) {
        throw Exception(
            'Invalid command format: expected at least command and data');
      }

      final command = commandStrings[0];
      final commandData = commandStrings[1];

      logger.info('[MainIsolate] Parsed complete command: "$command" with data: "$commandData" for ackReplyId: $ackReplyId');

      final replyId = commandStrings.length > 2 ? commandStrings[2] : null;
      if (replyId != null) {
        logger.info('Reply ID: "$replyId"');
        if (command == checkStatusCommand || command == scanWifiCommand) {
          chunkedResponseReplyIds.add(replyId);
        }
      }

      // Send metric with cached device ID
      MetricService().sendEvent(
        'command_received',
        stringData: [command, commandData],
      );

      CommandService().handleCommand(command, commandData, replyId);
    } catch (e, stackTrace) {
           logger.severe('[MainIsolate] Error parsing assembled command for $ackReplyId: $e');
           logger.severe('Stack trace: $stackTrace');
           notify(ackReplyId, {'success': false, 'error': 'Failed to parse assembled command'});
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
      if (data == nullptr || length <= 0) return;
      // Create an immediate immutable copy of the data
      rawBytes = List<int>.unmodifiable(data.asTypedList(length));

      // Release the FFI data using C's free function
      _instance._bindings.bluetooth_free_data(data);

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

      _instance._ffiCallbackSendPort.send(_CredentialsArgs(credentials));
    } catch (e, stackTrace) {
      _instance._ffiCallbackSendPort.send(_FfiErrorArgs('ConnectionResultCallback', e, stackTrace));
    }
  }

  void notify(String replyID, Map<String, dynamic> payload) {
    try {
      if (chunkedResponseReplyIds.contains(replyID) ||
          replyID == statusChangedReplyId) {
        _sendDataByChunks(payload, replyID);
        chunkedResponseReplyIds.remove(replyID);
      } else {
        final encodedMessage = VarintParser.encodeStringArray([
          replyID,
          jsonEncode(payload),
        ]);
        _sendData(encodedMessage);
      }

      logger.info('Sent notification: $replyID with payload: $payload');
    } catch (e) {
      logger.severe('Error sending notification: $e');
    }
  }

  int _getMaxChunkDataSize() {
    const mtu = 512;
    const messageOverhead = 7;
    const chunkMapOverhead = 22;

    // Calculate available space for payload
    // Convert binary data to base64 encoding (which increases size by ~33%)
    // Base64 encoding works by converting every 3 bytes of binary data into 4 ASCII characters

    var maxRawDataSize = mtu - messageOverhead - chunkMapOverhead;
    maxRawDataSize = maxRawDataSize - (maxRawDataSize % 4);

    final maxChunkDataSize =
        (maxRawDataSize * 0.75).floor(); // Base64 encoding factor

    return maxChunkDataSize;
  }

  void _sendDataByChunks(Map<String, dynamic> payload, String replyID) {
    final payloadString = jsonEncode(payload);
    List<int> payloadBytes = utf8.encode(payloadString);
    logger.info('payloadBytes: ${payloadBytes.length}');

    final maxChunkDataSize = _getMaxChunkDataSize();
    final totalChunks = (payloadBytes.length / maxChunkDataSize).ceil();

    logger.info(
        'Splitting message into $totalChunks chunks of ~$maxChunkDataSize bytes each');

    for (var i = 0; i < totalChunks; i++) {
      final start = i * maxChunkDataSize;
      final end = (start + maxChunkDataSize) > payloadBytes.length
          ? payloadBytes.length
          : start + maxChunkDataSize;

      final chunkData = payloadBytes.sublist(start, end);
      final chunkMap = {
        'i': i,
        't': totalChunks,
        'd': base64.encode(chunkData),
      };

      final encodedMessage = VarintParser.encodeStringArray([
        replyID,
        jsonEncode(chunkMap),
      ]);

      logger.info(
          'Sending chunk $i/${totalChunks - 1} with ${encodedMessage.length} bytes');
      _sendData(encodedMessage, chunkIndex: i);

      // Use adaptive delay based on chunk size
      if (totalChunks > 1) {
        final delayMs = (chunkData.length / 1000).ceil() * 10;
        final adjustedDelay = delayMs.clamp(20, 100);
        Future.delayed(Duration(milliseconds: adjustedDelay));
      }
    }
  }

  void _sendData(List<int> data, {int? chunkIndex}) {
    final Pointer<Uint8> pointer = calloc<Uint8>(data.length);
    final bytes = pointer.asTypedList(data.length);

    final logPrefix = chunkIndex != null ? 'Chunk $chunkIndex: ' : '';
    logger.info('${logPrefix}Copying ${data.length} bytes to FFI buffer');

    for (var i = 0; i < data.length; i++) {
      bytes[i] = data[i];
    }

    final hexString =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    logger.info('${logPrefix}Copied bytes (hex): $hexString');

    _bindings.bluetooth_notify(pointer, data.length);
    calloc.free(pointer);
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

  void sendEngineeringData(List<int> data) {
    try {
      final Pointer<Uint8> pointer = calloc<Uint8>(data.length);
      final bytes = pointer.asTypedList(data.length);

      logger.info('Sending ${data.length} bytes of engineering data');

      for (var i = 0; i < data.length; i++) {
        bytes[i] = data[i];
      }

      final hexString =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      logger.info('Engineering data (hex): $hexString');

      _bindings.bluetooth_send_engineering_data(pointer, data.length);
      calloc.free(pointer);
    } catch (e) {
      logger.severe('Error sending engineering data: $e');
    }
  }
}
