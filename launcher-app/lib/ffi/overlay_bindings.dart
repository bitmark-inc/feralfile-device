import 'dart:ffi';
import 'dart:io';

// Function signatures
typedef OverlayInitNative = Int32 Function();
typedef OverlayInitDart = int Function();

typedef OverlayMoveCursorNative = Void Function(Int32 x, Int32 y);
typedef OverlayMoveCursorDart = void Function(int x, int y);

typedef OverlaySetRotationNative = Void Function(Int32 degrees);
typedef OverlaySetRotationDart = void Function(int degrees);

typedef OverlayCleanupNative = Void Function();
typedef OverlayCleanupDart = void Function();

class OverlayBindings {
  late DynamicLibrary _lib;
  late OverlayInitDart overlay_init;
  late OverlayMoveCursorDart overlay_move_cursor;
  late OverlaySetRotationDart overlay_set_rotation;
  late OverlayCleanupDart overlay_cleanup;

  OverlayBindings() {
    if (Platform.isLinux) {
      _lib = DynamicLibrary.open('liboverlay_service.so');
    } else {
      throw UnsupportedError('This library is only supported on Linux.');
    }

    overlay_init = _lib
        .lookup<NativeFunction<OverlayInitNative>>('overlay_init')
        .asFunction();

    overlay_move_cursor = _lib
        .lookup<NativeFunction<OverlayMoveCursorNative>>('overlay_move_cursor')
        .asFunction();

    overlay_set_rotation = _lib
        .lookup<NativeFunction<OverlaySetRotationNative>>(
            'overlay_set_rotation')
        .asFunction();

    overlay_cleanup = _lib
        .lookup<NativeFunction<OverlayCleanupNative>>('overlay_cleanup')
        .asFunction();
  }
}
