import '../ffi/overlay_bindings.dart';
import 'logger.dart';

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  late OverlayBindings _bindings;
  bool _isInitialized = false;

  factory OverlayService() {
    return _instance;
  }

  OverlayService._internal() {
    _bindings = OverlayBindings();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    logger.info('Initializing overlay service...');
    final result = _bindings.overlay_init();
    if (result != 0) {
      logger.severe('Failed to initialize overlay service');
      return;
    }
    _isInitialized = true;
    logger.info('Overlay service initialized successfully');
  }

  void showRotationIndicator(int degrees) {
    if (!_isInitialized) {
      logger.warning('Overlay service not initialized');
      return;
    }
    _bindings.overlay_set_rotation(degrees);
  }

  void dispose() {
    if (_isInitialized) {
      _bindings.overlay_cleanup();
      _isInitialized = false;
    }
  }
}
