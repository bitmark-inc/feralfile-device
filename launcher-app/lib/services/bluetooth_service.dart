// lib/services/bluetooth_service.dart

import 'dart:ffi';
import 'dart:isolate';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:feralfile/models/chunk.dart';
import 'package:feralfile/services/logger.dart';
import 'package:ffi/ffi.dart';
import 'package:feralfile/generated/protos/command.pb.dart';

import '../ffi/bindings.dart';
import '../models/wifi_credentials.dart';
import '../services/command_service.dart';
import '../services/metric_service.dart';
import '../utils/varint_parser.dart';

const statusChangedReplyId = 'statusChanged';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;

  final BluetoothBindings _bindings = BluetoothBindings();
  final CommandService _commandService = CommandService();
  static void Function(WifiCredentials)? _onCredentialsReceived;
  static final _commandPort = ReceivePort();
  static final Map<String, Map<int, List<int>>> _chunkData = {};
  static final Set<String> chunkedResponseReplyIds = {};

  // Store both callbacks
  late final NativeCallable<ConnectionResultCallbackNative> _setupCallback;
  late final NativeCallable<CommandCallbackNative> _cmdCallback;

  String? _cachedDeviceId;

  BluetoothService._internal() {
    _commandService.initialize(this);
    _bindings.bluetooth_set_logfile(logFilePath.toNativeUtf8());
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

      int startResult = _bindings.bluetooth_start(
          _setupCallback.nativeFunction, _cmdCallback.nativeFunction);

      if (startResult != 0) {
        logger.warning('Failed to start Bluetooth service.');
        _setupCallback.close();
        _cmdCallback.close();
        return false;
      }

      logger.info('Bluetooth service started. Waiting for connections...');

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
    _commandPort.close();
  }

  Stream<CommandData> get commandStream => _commandService.commandStream;

  /// Static callback for incoming command data from FFI.
  static void _staticCommandCallback(
      int success, Pointer<Uint8> data, int length) {
    try {
      if (data == nullptr || length <= 0) {
        logger.warning('Received empty or invalid command data');
        return;
      }

      // Make an immutable copy of the data.
      final dataCopy = List<int>.unmodifiable(data.asTypedList(length));
      _instance._bindings.bluetooth_free_data(data);

      // Process chunked data.
      final chunkInfo = ChunkInfo.fromData(dataCopy);
      _validateChunkIndices(chunkInfo);
      logger.info('Processing chunk ${chunkInfo.index} of ${chunkInfo.total}');
      _storeChunk(chunkInfo);
      _sendChunkAcknowledgement(chunkInfo);

      // If all chunks have arrived, process the complete command.
      if (_chunkData[chunkInfo.ackReplyId]!.length == chunkInfo.total) {
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
    _chunkData[info.ackReplyId] ??= {};
    _chunkData[info.ackReplyId]![info.index] = info.data;
  }

  /// Send a chunk acknowledgement using a protobuf CommandResponse.
  static void _sendChunkAcknowledgement(ChunkInfo info) {
    logger.info('Notifying back for chunk ${info.index}');
    final response = CommandResponse()
      ..success = true
      ..message = 'Chunk ${info.index} received'
      ..data = jsonEncode({'chunkIndex': info.index});
    _instance.notify(info.ackReplyId, response);
  }

  /// When all chunks are received, combine them and decode using protobuf.
  static void _processCompleteCommand(ChunkInfo info) {
    final completeCommand =
        _chunkData[info.ackReplyId]!.values.expand((chunk) => chunk).toList();
    _chunkData.remove(info.ackReplyId);

    try {
      final commandData = CommandData.fromBuffer(completeCommand);
      logger.info(
          'Parsed complete command: "${commandData.command}" with data: "${commandData.data}"');
      if (commandData.replyId.isNotEmpty) {
        logger.info('Reply ID: "${commandData.replyId}"');
        if (commandData.command == 'checkStatus') {
          chunkedResponseReplyIds.add(commandData.replyId);
        }
      }
      MetricService().sendEvent(
          'command_received', 
          userId: commandData.userInfo.id, 
          userName: commandData.userInfo.name, 
          stringData: [commandData.command, commandData.data]);
      CommandService().handleCommand(commandData);
    } catch (e) {
      logger.severe('Error processing complete command: $e');
    }
  }

  /// Static callback for connection results.
  static void _staticConnectionResultCallback(
    int success,
    Pointer<Uint8> data,
    int length,
  ) {
    try {
      final rawBytes = List<int>.unmodifiable(data.asTypedList(length));
      _instance._bindings.bluetooth_free_data(data);
      final hexString =
          rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      logger.info('Raw bytes (hex): $hexString');

      // For WiFi credentials, we assume a varint‑encoded string array.
      final (strings, _) = VarintParser.parseToStringArray(rawBytes, 0);
      if (strings.length < 2) {
        throw Exception(
            'Invalid WiFi credentials format: expected SSID and password');
      }

      final ssid = strings[0];
      final password = strings[1];
      logger.info('Received WiFi credentials - SSID: $ssid, password: $password');
      final credentials = WifiCredentials(ssid: ssid, password: password);

      if (_onCredentialsReceived != null) {
        _onCredentialsReceived!(credentials);
      }
    } catch (e) {
      logger.warning('Error processing WiFi credentials: $e');
    }
  }

  /// send notifications using protobuf binary data.
  void notify(String replyID, CommandResponse response) {
    final payload = response.writeToBuffer();
    try {
      if (chunkedResponseReplyIds.contains(replyID) ||
          replyID == statusChangedReplyId) {
        _sendDataByChunksBinary(payload, replyID);
        chunkedResponseReplyIds.remove(replyID);
      } else {
        final encodedMessage = VarintParser.encodeStringArray([
          replyID,
          jsonEncode(payload),
        ]);
        _sendData(encodedMessage);
      }
      logger.info(
          'Sent notification: $replyID with payload of ${payload.length} bytes');
    } catch (e) {
      logger.severe('Error sending notification: $e');
    }
  }

  /// Calculate the maximum size allowed per chunk.
  int _getMaxChunkDataSize() {
    const mtu = 512;
    const messageOverhead = 7;
    const chunkMapOverhead = 22;

    var maxRawDataSize = mtu - messageOverhead - chunkMapOverhead;
    maxRawDataSize = maxRawDataSize - (maxRawDataSize % 4);
    final maxChunkDataSize =
        (maxRawDataSize * 0.75).floor(); // Base64 encoding factor (if needed)
    return maxChunkDataSize;
  }

  /// Send the binary payload in chunks.
  void _sendDataByChunksBinary(List<int> payload, String replyID) {
    final maxChunkDataSize = _getMaxChunkDataSize();
    final totalChunks = (payload.length / maxChunkDataSize).ceil();
    logger.info(
        'Splitting message into $totalChunks chunks of ~$maxChunkDataSize bytes each');

    for (var i = 0; i < totalChunks; i++) {
      final start = i * maxChunkDataSize;
      final end =
          (start + maxChunkDataSize) > payload.length ? payload.length : start + maxChunkDataSize;
      final chunkData = payload.sublist(start, end);
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

  /// Copy the data into an FFI buffer and send it.
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
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final mac = getMacAddress();
    if (mac == null) {
      _cachedDeviceId = 'FF-X1-000000';
      return _cachedDeviceId!;
    }
    final bytes = utf8.encode(mac);
    final hash = md5.convert(bytes);
    final hashStr = hash.bytes.sublist(0, 6).map((byte) {
      return ((byte % 36) < 10)
          ? ((byte % 36) + 48)
          : ((byte % 36) + 55);
    }).map((charCode) => String.fromCharCode(charCode)).join();
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