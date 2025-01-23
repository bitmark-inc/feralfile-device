// lib/ffi/bindings.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Define the callback signature
typedef ConnectionResultCallbackNative = Void Function(
    Int32 success, Pointer<Uint8> data, Int32 length);
typedef ConnectionResultCallbackDart = void Function(
    int success, Pointer<Uint8>, int length);

// Define the function signatures
typedef BluetoothInitNative = Int32 Function(Pointer<Utf8> deviceName);
typedef BluetoothInitDart = int Function(Pointer<Utf8> deviceName);

typedef BluetoothStartNative = Int32 Function(
  Pointer<NativeFunction<ConnectionResultCallbackNative>> setup_callback,
  Pointer<NativeFunction<CommandCallbackNative>> cmd_callback,
);
typedef BluetoothStartDart = int Function(
  Pointer<NativeFunction<ConnectionResultCallbackNative>> setup_callback,
  Pointer<NativeFunction<CommandCallbackNative>> cmd_callback,
);

typedef BluetoothStopNative = Void Function();
typedef BluetoothStopDart = void Function();

typedef SetLogFileNative = Void Function(Pointer<Utf8> path);
typedef SetLogFileDart = void Function(Pointer<Utf8> path);

// Add command callback typedef
typedef CommandCallbackNative = Void Function(
    Int32 success, Pointer<Uint8> data, Int32 length);
typedef CommandCallbackDart = void Function(
    int success, Pointer<Uint8>, int length);

// Add to existing typedefs
typedef BluetoothNotifyNative = Void Function(
    Pointer<Uint8> data, Int32 length);
typedef BluetoothNotifyDart = void Function(Pointer<Uint8> data, int length);

class BluetoothBindings {
  late DynamicLibrary _lib;

  late final BluetoothInitDart bluetooth_init;
  late BluetoothStartDart bluetooth_start;
  late BluetoothStopDart bluetooth_stop;
  late SetLogFileDart bluetooth_set_logfile;
  late BluetoothNotifyDart bluetooth_notify;

  BluetoothBindings() {
    // Load the shared library
    if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libbluetooth_service.so');
    } else {
      throw UnsupportedError('This library is only supported on Linux.');
    }

    // Lookup the functions
    _initializeFunctions();
  }

  void _initializeFunctions() {
    bluetooth_init = _lib
        .lookup<NativeFunction<BluetoothInitNative>>('bluetooth_init')
        .asFunction();

    bluetooth_start = _lib
        .lookup<NativeFunction<BluetoothStartNative>>('bluetooth_start')
        .asFunction();

    bluetooth_stop = _lib
        .lookup<NativeFunction<BluetoothStopNative>>('bluetooth_stop')
        .asFunction();

    bluetooth_set_logfile = _lib
        .lookup<NativeFunction<SetLogFileNative>>('bluetooth_set_logfile')
        .asFunction();

    bluetooth_notify = _lib
        .lookup<NativeFunction<BluetoothNotifyNative>>('bluetooth_notify')
        .asFunction();
  }
}
