import 'package:connectivity_plus/connectivity_plus.dart';

class InternetConnectivityService {
  // Singleton instance
  static final InternetConnectivityService _instance =
      InternetConnectivityService._internal();
  factory InternetConnectivityService() => _instance;
  InternetConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  bool isOnline = false;

  /// Stream to listen for connectivity changes.
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map((status) {
        isOnline = status != ConnectivityResult.none;
        print('Internet connectivity changed: $isOnline');
        return isOnline;
      });

  /// Starts monitoring connectivity changes
  void startMonitoring() async {
    // Kiểm tra trạng thái kết nối ban đầu
    final status = await _connectivity.checkConnectivity();
    isOnline = status != ConnectivityResult.none;
  }

  Future<bool> checkConnectivity() async {
    final status = await _connectivity.checkConnectivity();
    return status != ConnectivityResult.none;
  }
}
