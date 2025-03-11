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

// Add these typedefs
typedef GetMacAddressNative = Pointer<Utf8> Function();
typedef GetMacAddressDart = Pointer<Utf8> Function();

// Add these typedefs after your existing typedefs
typedef BluetoothFreeDataNative = Void Function(Pointer<Uint8> data);
typedef BluetoothFreeDataDart = void Function(Pointer<Uint8> data);

// Add these typedefs
typedef BluetoothSendEngineeringDataNative = Void Function(
    Pointer<Uint8> data, Int32 length);
typedef BluetoothSendEngineeringDataDart = void Function(
    Pointer<Uint8> data, int length);

class BluetoothBindings {
  late DynamicLibrary _lib;

  late final BluetoothInitDart bluetooth_init;
  late BluetoothStartDart bluetooth_start;
  late BluetoothStopDart bluetooth_stop;
  late SetLogFileDart bluetooth_set_logfile;
  late BluetoothNotifyDart bluetooth_notify;
  late GetMacAddressDart bluetooth_get_mac_address;
  late BluetoothFreeDataDart bluetooth_free_data;
  late BluetoothSendEngineeringDataDart bluetooth_send_engineering_data;

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

    bluetooth_get_mac_address = _lib
        .lookup<NativeFunction<GetMacAddressNative>>(
            'bluetooth_get_mac_address')
        .asFunction();

    // Add this lookup
    bluetooth_free_data = _lib
        .lookup<NativeFunction<BluetoothFreeDataNative>>('bluetooth_free_data')
        .asFunction();

    // Add this lookup
    bluetooth_send_engineering_data = _lib
        .lookup<NativeFunction<BluetoothSendEngineeringDataNative>>(
            'bluetooth_send_engineering_data')
        .asFunction();
  }
}
