import 'dart:async';
import 'dart:io';

class InternetConnectivityService {
  // Singleton instance
  static final InternetConnectivityService _instance =
      InternetConnectivityService._internal();
  factory InternetConnectivityService() => _instance;
  InternetConnectivityService._internal();

  bool isOnline = false;
  Timer? _timer;
  final List<String> _pingAddresses = ['8.8.8.8', '1.1.1.1', '9.9.9.9'];
  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  /// Stream to listen for connectivity changes.
  Stream<bool> get onStatusChange => _connectivityController.stream;

  /// Starts periodic monitoring every 5 seconds.
  void startMonitoring() async {
    // Avoid starting multiple timers.
    _updateConnectivity();
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(Duration(seconds: 5), (_) async {
      _updateConnectivity();
      _connectivityController.add(isOnline);
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  void _updateConnectivity() async {
    bool online = await checkConnectivity();
    if (online != isOnline) {
      isOnline = online;
      logger.info('Internet connectivity changed: $isOnline');
    }
  }

  /// Pings each target address. Returns true if at least one responds.
  Future<bool> checkConnectivity() async {
    for (var address in _pingAddresses) {
      try {
        // Use the Linux ping command; '-c 1' sends one ping.
        ProcessResult result = await Process.run('ping', ['-c', '1', address]);
        if (result.exitCode == 0) {
          return true;
        }
      } catch (e) {
        // Ignore error and try next address.
      }
    }
    return false;
  }
}
